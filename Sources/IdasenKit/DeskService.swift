import Foundation

public struct LogEntry: Identifiable, Equatable, Sendable {
    public enum Level: String, Sendable {
        case info
        case warning
        case error
    }

    public let id = UUID()
    public var date: Date
    public var level: Level
    public var message: String

    public init(date: Date = Date(), level: Level, message: String) {
        self.date = date
        self.level = level
        self.message = message
    }
}

/// High-level desk controller: owns the transport, the movement state machine,
/// automatic reconnection and all safety watchdogs.
@MainActor
public final class DeskService: ObservableObject, DeskLinkDelegate {

    // MARK: Published state

    @Published public private(set) var connection: ConnectionState = .idle
    @Published public private(set) var bluetooth: BluetoothAvailability = .unknown
    @Published public private(set) var discovered: [DiscoveredDesk] = []
    @Published public private(set) var isScanning = false

    @Published public private(set) var heightMM: Double?
    @Published public private(set) var speedMMps: Double = 0
    @Published public private(set) var movement: MovementDirection = .stopped
    @Published public private(set) var lastSampleAt: Date?
    @Published public private(set) var lastRawSample: DeskHeightSample?
    @Published public private(set) var progress: MoveProgress?

    @Published public private(set) var lastError: DeskError?
    @Published public private(set) var holdingDirection: MovementDirection = .stopped
    @Published public private(set) var isReady = false
    @Published public private(set) var log: [LogEntry] = []

    public var connectedDeskName: String? { link.connectedDeskName }

    public var isConnected: Bool { connection.isConnected && isReady }
    public var isMoving: Bool { movement != .stopped }

    // MARK: Callbacks

    /// Called when an automatic move reaches its target.
    public var onArrived: ((Double) -> Void)?
    /// Called when an automatic move fails, with the reason.
    public var onMoveFailed: ((DeskError) -> Void)?
    /// Called for transport level problems that the user should know about.
    public var onError: ((DeskError) -> Void)?
    /// Called with user-facing notices (one-off informative messages).
    public var onNotice: ((String) -> Void)?

    // MARK: Configuration

    public var settings: AppSettings = AppSettings() {
        didSet {
            if settings.demoMode != oldValue.demoMode {
                switchLink(demo: settings.demoMode)
            }
            if settings.historyRetentionDays != oldValue.historyRetentionDays {
                activity?.configure(retentionDays: settings.historyRetentionDays)
            }
        }
    }

    public weak var activity: ActivityRecorder?

    // MARK: Internals

    private var bluetoothLinkStorage: BluetoothDeskLink?
    private let simulatedLink = SimulatedDeskLink()

    /// Testing seam: lets tests drive the simulated controller's quirks.
    public var simulatedLinkForTesting: SimulatedDeskLink { simulatedLink }

    /// The active transport. The Bluetooth stack is created on first use so
    /// demo mode never touches CoreBluetooth (and never triggers its prompts).
    private var link: DeskLink {
        if settings.demoMode { return simulatedLink }
        if let storage = bluetoothLinkStorage { return storage }
        let created = BluetoothDeskLink()
        created.delegate = self
        bluetoothLinkStorage = created
        return created
    }

    private var holdTimer: Timer?
    private var holdStartedAt: Date?
    private var holdPeakSpeedMMps: Double = 0
    private var moveTimer: Timer?
    private var keepAliveTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempt = 0
    private var userWantsConnection = false

    /// How an automatic move is driven.
    ///
    /// `.referenceInput` is the precise LINAK "go to position" channel. Some
    /// controllers ignore it, so the service falls back to raise/lower commands
    /// with a braking-distance controller.
    private enum MoveMode {
        case referenceInput
        case stepCommands
    }

    /// Active automatic move.
    private struct ActiveMove {
        var target: Double
        var start: Double
        var tolerance: Double
        var startedAt: Date
        var lastProgressAt: Date
        var lastHeight: Double
        var mode: MoveMode
        /// True while coasting to a stop in `.stepCommands` mode.
        var braking: Bool = false
        var brakeStartedAt: Date?
        var cycles: Int = 0
        var zeroSpeedTicks: Int = 0
        var stallTicks: Int = 0
        var stallRetries: Int = 0
        var tick: Int = 0
        var peakSpeedMMps: Double = 0
    }

    private var activeMove: ActiveMove?

    /// Cache the fallback only after repeated failures, since a single missed
    /// reference command can be a transient BLE or wake-up issue.
    private var controllerUsesStepCommands = false
    private var referenceInputFailures = 0

    private var lastHeight: Double?
    private var lastHeightChangeAt: Date = .distantPast
    private var previousHeightSample: (heightMM: Double, at: Date)?

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        simulatedLink.delegate = self
        startKeepAlive()
    }

    isolated deinit {
        holdTimer?.invalidate()
        moveTimer?.invalidate()
        keepAliveTimer?.invalidate()
        reconnectTimer?.invalidate()
    }

    // MARK: - Scanning

    public func startScanning() {
        discovered = []
        isScanning = true
        userWantsConnection = false
        appendLog(.info, "Scanning for desks…")
        link.startScan()
    }

    public func stopScanning() {
        isScanning = false
        link.stopScan()
        if case .scanning = connection { connection = .idle }
    }

    // MARK: - Connecting

    public func connect(to desk: DiscoveredDesk) {
        stopScanning()
        userWantsConnection = true
        reconnectAttempt = 0
        appendLog(.info, "Connecting to \(desk.name)…")
        link.connect(to: desk.id, name: desk.name)
    }

    /// Attempts to reconnect to the previously used desk.
    @discardableResult
    public func connectSavedDesk() -> Bool {
        userWantsConnection = true
        reconnectAttempt = 0
        let result = link.connectSaved()
        if result {
            appendLog(.info, "Reconnecting to \(link.connectedDeskName ?? "saved desk")…")
        }
        return result
    }

    public func connectIfConfigured() {
        guard settings.autoConnect else { return }
        // The transport may know a desk even when the settings file was reset.
        connectSavedDesk()
    }

    public func disconnect() {
        userWantsConnection = false
        reconnectTimer?.invalidate()
        cancelMovementLoops()
        sendStopBytes()
        isReady = false
        link.disconnect()
        activity?.closeOpenSegment()
        appendLog(.info, "Disconnected")
    }

    public func forgetDesk() {
        disconnect()
        link.forgetSaved()
        settings.lastDeskID = nil
        settings.lastName = nil
        heightMM = nil
        lastSampleAt = nil
        lastHeight = nil
        previousHeightSample = nil
        speedMMps = 0
        appendLog(.info, "Forgot saved desk")
    }

    // MARK: - Movement

    /// Starts continuous movement while held. Repeat-writes keep the desk alive.
    public func startHold(_ direction: MovementDirection) {
        guard direction != .stopped else { return }
        guard isConnected else {
            lastError = .notConnected
            return
        }
        if holdingDirection == direction, holdTimer != nil { return }
        if activeMove != nil || holdTimer != nil { sendStopBytes() }
        cancelMove(reason: "hold")
        holdingDirection = direction
        movement = direction
        prepareForMove()
        sendCommand(direction == .up ? .up : .down)

        appendLog(.info, direction == .up ? "Raising (held)" : "Lowering (held)")

        holdTimer?.invalidate()
        holdStartedAt = Date()
        holdPeakSpeedMMps = 0
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let holdStartedAt = self.holdStartedAt,
                    Date().timeIntervalSince(holdStartedAt) >= self.settings.safetyMaxRunSeconds {
                    self.stop()
                    self.lastError = .moveTimeout
                    self.onMoveFailed?(.moveTimeout)
                    return
                }
                self.sendCommand(direction == .up ? .up : .down)
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    /// Stops continuous movement started by ``startHold(_:)``.
    public func endHold() {
        guard holdTimer != nil else { return }
        let elapsed = Date().timeIntervalSince(holdStartedAt ?? Date())
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartedAt = nil
        holdingDirection = .stopped
        // A hold uses the command channel only. The reference-input abort is
        // reserved for cancelling an automatic move or an emergency stop.
        sendCommand(.stop)
        appendLog(.info, String(format: "Hold released after %.1f s (peak %.1f cm/s)", elapsed, holdPeakSpeedMMps / 10))
    }

    /// Stops everything immediately.
    public func stop() {
        cancelMovementLoops()
        sendStopBytes()
        movement = .stopped
        progress = nil
        appendLog(.info, "Stop requested")
    }

    /// Moves the desk to an absolute height and tracks progress.
    public func go(toMM target: Double, tolerance: Double? = nil, announce: Bool = true) {
        guard isConnected, let current = heightMM else {
            lastError = .notConnected
            return
        }
        guard settings.heightScale.contains(target) else {
            lastError = .invalidTarget
            return
        }
        let resolvedTolerance = tolerance ?? settings.defaultMoveToleranceMM
        // The target channel can replan an ongoing move. Keep its acceleration
        // continuous when the new target is still ahead in the same direction.
        let continuesPositionMove = activeMove.map {
            $0.mode == .referenceInput
                && movement == (target > current ? .up : .down)
                && ($0.target - current) * (target - current) > 0
                && abs(target - current) > resolvedTolerance
        } ?? false
        if !continuesPositionMove, activeMove != nil || holdTimer != nil { sendStopBytes() }
        cancelMove(reason: "new target")
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartedAt = nil
        holdingDirection = .stopped

        let clamped = settings.heightScale.clamp(target)
        if abs(clamped - current) <= (tolerance ?? settings.defaultMoveToleranceMM) {
            appendLog(.info, "Already at \(HeightScale.describe(clamped))")
            onArrived?(current)
            return
        }

        activeMove = ActiveMove(
            target: clamped,
            start: current,
            tolerance: resolvedTolerance,
            startedAt: Date(),
            lastProgressAt: Date(),
            lastHeight: current,
            mode: controllerUsesStepCommands || !link.hasReferenceInput ? .stepCommands : .referenceInput
        )
        progress = MoveProgress(targetMM: clamped, startMM: current, currentMM: current)
        if announce {
            appendLog(.info, "Moving to \(HeightScale.describe(clamped))")
        }

        if continuesPositionMove {
            link.writeReference(bytes: settings.heightScale.referenceInputBytes(forMillimeters: clamped))
        } else {
            prepareForMove()
        }

        moveTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepMove() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        moveTimer = timer
        // The first tick is deliberately left to the timer so the wake-up and
        // stop preflight reach the controller before the reference input.
    }

    /// Small relative adjustment.
    public func nudge(byMM delta: Double) {
        guard let current = heightMM else { return }
        go(toMM: current + delta, announce: false)
    }

    /// Sends a raw movement command (used by the menu bar and tests).
    public func sendCommand(_ command: IdasenCommand) {
        guard isConnected else { return }
        link.write(command: command)
    }

    public func wakeUp() {
        guard isConnected else { return }
        link.write(command: .wakeUp)
    }

    // MARK: - Movement internals

    private func prepareForMove() {
        if settings.warmUpBeforeMoves {
            // The controller only accepts reference-input moves after a wake-up
            // and a stop; both are required by the LINAK protocol.
            link.write(command: .wakeUp)
            link.write(command: .stop)
        }
        if settings.dpgCompatibility, let bluetooth = link as? BluetoothDeskLink {
            bluetooth.wakeDPG()
        }
    }

    private func sendStopBytes() {
        guard isConnected else { return }
        link.write(command: .stop)
        if link.hasReferenceInput {
            link.writeReference(bytes: referenceInputStopBytes)
        }
    }

    private func cancelMove(reason: String) {
        guard activeMove != nil else { return }
        moveTimer?.invalidate()
        moveTimer = nil
        activeMove = nil
        progress = nil
        if reason != "silent" {
            appendLog(.info, "Move cancelled (\(reason))")
        }
    }

    private func cancelMovementLoops() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartedAt = nil
        holdingDirection = .stopped
        moveTimer?.invalidate()
        moveTimer = nil
        activeMove = nil
    }

    private func stepMove() {
        guard var move = activeMove else { return }
        guard isConnected, let current = heightMM else {
            finishMove(.failed(.connectionLost))
            return
        }
        move.tick += 1
        let now = Date()
        move.peakSpeedMMps = max(move.peakSpeedMMps, speedMMps)

        let atTarget = abs(current - move.target) <= move.tolerance
        let speedSmall = speedMMps < 8

        // Let the position controller finish its own arrival ramp before
        // reporting success. A low estimated speed alone is not a settled desk.
        let controllerStopped = move.mode == .stepCommands || lastRawSample?.speed == 0
        if atTarget && speedSmall && controllerStopped {
            move.zeroSpeedTicks += 1
        } else {
            move.zeroSpeedTicks = 0
        }

        if move.zeroSpeedTicks >= 2 {
            activeMove = move
            finishMove(.arrived)
            return
        }

        // Progress tracking / stall detection.
        if abs(current - move.lastHeight) >= 0.5 {
            move.lastHeight = current
            move.lastProgressAt = now
            move.stallTicks = 0
        } else if !atTarget {
            move.stallTicks += 1
        } else {
            move.stallTicks = 0
        }

        // The reference-input channel is ignored by some controllers. Detect
        // that quickly and switch this and future moves to step commands.
        if move.mode == .referenceInput, abs(current - move.start) >= 2 {
            referenceInputFailures = 0
        }
        if move.mode == .referenceInput, !atTarget, move.tick >= 12,
           abs(current - move.start) < 2 {
            move.mode = .stepCommands
            move.stallTicks = 0
            move.stallRetries = 0
            referenceInputFailures += 1
            controllerUsesStepCommands = referenceInputFailures >= 2
            appendLog(.warning, "Reference input had no effect — using raise/lower commands")
            onNotice?("This controller only supports raise/lower moves, so heights may be a few millimetres off.")
        }

        if move.stallTicks >= 25 { // ~2.5 s without progress
            move.stallTicks = 0
            move.stallRetries += 1
            if move.stallRetries > 3 {
                activeMove = move
                finishMove(.failed(.moveStalled))
                return
            }
            appendLog(.warning, "Stalled — retrying move")
            prepareForMove()
        }

        // Collision safety net.
        if (move.target > move.start && current < move.start - 20)
            || (move.target < move.start && current > move.start + 20) {
            activeMove = move
            finishMove(.failed(.moveBlocked))
            return
        }

        // Hard timeout.
        if now.timeIntervalSince(move.startedAt) > settings.safetyMaxRunSeconds {
            activeMove = move
            finishMove(.failed(.moveTimeout))
            return
        }

        switch move.mode {
        case .referenceInput:
            if move.tick >= 1 {
                let bytes = settings.heightScale.referenceInputBytes(forMillimeters: move.target)
                link.writeReference(bytes: bytes)
            }

        case .stepCommands:
            // Bang-bang controller with a braking distance so the desk does not
            // coast past the target after the last command.
            let brakeDistance = max(move.tolerance, speedMMps * 0.12)
            let distance = move.target - current

            if move.braking {
                // Waiting for the desk to come to rest.
                if speedSmall || (move.brakeStartedAt.map { now.timeIntervalSince($0) > 1.6 } ?? false) {
                    if abs(distance) <= move.tolerance {
                        activeMove = move
                        finishMove(.arrived)
                        return
                    }
                    // Under/overshot: one more short burst.
                    move.braking = false
                    move.brakeStartedAt = nil
                    move.cycles += 1
                    if move.cycles > 6 {
                        activeMove = move
                        finishMove(abs(distance) <= move.tolerance * 2 ? .arrived : .failed(.moveStalled))
                        return
                    }
                    link.write(command: distance > 0 ? .up : .down)
                }
            } else if abs(distance) <= brakeDistance {
                link.write(command: .stop)
                move.braking = true
                move.brakeStartedAt = now
            } else {
                link.write(command: distance > 0 ? .up : .down)
            }
        }

        if move.tick % 10 == 0 {
            link.requestHeight()
        }

        let remaining = abs(move.target - current)
        let eta = speedMMps > 5 ? remaining / speedMMps : nil
        progress = MoveProgress(
            targetMM: move.target,
            startMM: move.start,
            currentMM: current,
            startedAt: move.startedAt,
            estimatedSecondsRemaining: eta
        )
        activeMove = move
    }

    private func finishMove(_ outcome: MoveOutcome) {
        let completedMove = activeMove
        moveTimer?.invalidate()
        moveTimer = nil
        activeMove = nil
        progress = nil
        sendStopBytes()

        switch outcome {
        case .arrived:
            if let completedMove {
                let elapsed = Date().timeIntervalSince(completedMove.startedAt)
                let finalError = (heightMM ?? completedMove.start) - completedMove.target
                let control: String
                switch completedMove.mode {
                case .referenceInput: control = "target channel"
                case .stepCommands: control = "raise/lower, \(completedMove.cycles) corrections"
                }
                appendLog(
                    .info,
                    String(
                        format: "Arrived at %@ in %.1f s (final error %+.1f mm; %@; peak %.1f cm/s)",
                        HeightScale.describe(completedMove.target), elapsed, finalError,
                        control, completedMove.peakSpeedMMps / 10
                    )
                )
                onArrived?(completedMove.target)
            }
        case .cancelled:
            break
        case .failed(let error):
            lastError = error
            appendLog(.error, error.localizedDescription)
            onMoveFailed?(error)
        }
    }

    // MARK: - Keep alive

    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isConnected else { return }
                if let last = self.lastSampleAt, Date().timeIntervalSince(last) < 4 { return }
                self.link.requestHeight()
            }
        }
    }

    // MARK: - DeskLinkDelegate

    public func linkDidChangeState(_ link: DeskLink, state: ConnectionState) {
        connection = state
        switch state {
        case .connected(let name):
            isReady = false
            controllerUsesStepCommands = false
            referenceInputFailures = 0
            settings.lastName = name
            appendLog(.info, "Connected to \(name)")
            if settings.notifyOnConnectionChanges {
                onConnectedNotification?(name)
            }
        case .idle:
            isReady = false
            heightMM = nil
            lastHeight = nil
            previousHeightSample = nil
            speedMMps = 0
            movement = .stopped
        default:
            break
        }
    }

    public func linkDidChangeBluetooth(_ link: DeskLink, availability: BluetoothAvailability) {
        bluetooth = availability
        if availability == .poweredOff {
            isReady = false
            heightMM = nil
            lastHeight = nil
            previousHeightSample = nil
            speedMMps = 0
            movement = .stopped
        }
    }

    public func link(_ link: DeskLink, didDiscover desk: DiscoveredDesk) {
        if let index = discovered.firstIndex(where: { $0.id == desk.id }) {
            discovered[index] = desk
        } else {
            discovered.append(desk)
        }
        discovered.sort { $0.rssi > $1.rssi }
    }

    public func linkDidBecomeReady(_ link: DeskLink) {
        guard !isReady else { return }
        isReady = true
        reconnectAttempt = 0
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        settings.lastDeskID = link.savedDeskID
        appendLog(.info, "Desk ready")
        link.requestHeight()
    }

    public func link(_ link: DeskLink, didUpdate sample: DeskHeightSample) {
        let height = settings.heightScale.millimeters(forRaw: sample.raw)
        let now = sample.receivedAt

        if let previous = lastHeight {
            if height > previous + 0.2 {
                if movement != .up { movement = .up }
                lastHeightChangeAt = now
            } else if height < previous - 0.2 {
                if movement != .down { movement = .down }
                lastHeightChangeAt = now
            } else if sample.speed == 0 {
                if movement != .stopped { movement = .stopped }
            }
        }

        if lastRawSample?.raw != sample.raw || lastRawSample?.speed != sample.speed {
            lastRawSample = sample
        }
        lastHeight = height
        if heightMM != height { heightMM = height }
        let speed = measuredSpeed(for: height, at: now, rawIsStopped: sample.speed == 0)
        if speedMMps != speed { speedMMps = speed }
        if holdingDirection != .stopped {
            holdPeakSpeedMMps = max(holdPeakSpeedMMps, speed)
        }
        // The UI only shows this timestamp to the second. Publishing every BLE
        // packet also invalidates views while the desk is sitting still.
        if lastSampleAt.map({ now.timeIntervalSince($0) >= 1 }) ?? true {
            lastSampleAt = now
        }

        if sample.speed == 0, now.timeIntervalSince(lastHeightChangeAt) > 0.4,
            movement != .stopped {
            movement = .stopped
        }

        activity?.record(
            heightMM: height,
            at: now,
            thresholdMM: sitStandThreshold
        )
    }

    /// The controller's raw speed field has no documented unit. Derive mm/s
    /// from calibrated position samples for braking, ETA, and the speed readout.
    private func measuredSpeed(for height: Double, at time: Date, rawIsStopped: Bool) -> Double {
        guard let previousHeightSample else {
            self.previousHeightSample = (height, time)
            return 0
        }
        let elapsed = time.timeIntervalSince(previousHeightSample.at)
        guard elapsed > 0 else { return speedMMps }
        let distance = abs(height - previousHeightSample.heightMM)
        if rawIsStopped && distance < 0.2 {
            self.previousHeightSample = (height, time)
            return 0
        }
        // Read responses can arrive next to notifications. Do not replace the
        // velocity baseline with a duplicate packet only milliseconds later.
        guard elapsed >= 0.04 else { return speedMMps }
        self.previousHeightSample = (height, time)
        guard elapsed < 2 else { return 0 }
        let instantaneous = distance / elapsed
        return (speedMMps * 0.65 + instantaneous * 0.35).rounded()
    }

    public func link(_ link: DeskLink, didFail error: DeskError) {
        lastError = error
        appendLog(.error, error.localizedDescription)

        switch error {
        case .bluetoothPoweredOff, .bluetoothUnauthorized, .bluetoothUnavailable,
             .characteristicMissing, .connectionFailed:
            if activeMove != nil || holdTimer != nil { stop() }
            onError?(error)
        default:
            break
        }

        if case .connectionLost = error, userWantsConnection, settings.reconnectAutomatically {
            scheduleReconnect()
        }
    }

    public func link(_ link: DeskLink, didReceiveStatus bytes: [UInt8]) {
        // The status characteristic reports the controller's movement state.
        // Currently informational only.
        _ = bytes
    }

    /// Notified when the connection comes up (used for user notifications).
    public var onConnectedNotification: ((String) -> Void)?

    // MARK: - Reconnection

    private func scheduleReconnect() {
        let attempt = reconnectAttempt + 1
        reconnectAttempt = attempt
        guard attempt <= 8 else {
            appendLog(.error, "Giving up reconnecting after \(attempt - 1) attempts")
            connection = .failed("Desk unreachable")
            return
        }
        let delays: [Double] = [1, 2, 3, 5, 8, 13, 21, 30]
        let delay = delays[min(attempt - 1, delays.count - 1)]
        connection = .reconnecting(attempt: attempt)
        appendLog(.warning, "Reconnecting in \(Int(delay)) s (attempt \(attempt))")
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.userWantsConnection else { return }
                self.link.connectSaved()
            }
        }
    }

    public func clearError() {
        lastError = nil
    }

    // MARK: - Helpers

    public var sitStandThreshold: Double {
        let sit = activitySitHeight
        let stand = activityStandHeight
        return settings.sitStandThreshold(sitMM: sit, standMM: stand)
    }

    /// Preset heights supplied by the app for activity classification.
    public var activitySitHeight: Double?
    public var activityStandHeight: Double?

    private func appendLog(_ level: LogEntry.Level, _ message: String) {
        log.insert(LogEntry(level: level, message: message), at: 0)
        if log.count > 300 { log.removeLast(log.count - 300) }
        if Self.debugLogging {
            FileHandle.standardError.write(Data("[idasen][\(level.rawValue)] \(message)\n".utf8))
        }
    }

    /// `--debug-log` on the command line mirrors the in-app log to stderr.
    public static let debugLogging = CommandLine.arguments.contains("--debug-log")

    private func switchLink(demo: Bool) {
        cancelMovementLoops()
        simulatedLink.disconnect()
        bluetoothLinkStorage?.disconnect()
        connection = .idle
        isReady = false
        heightMM = nil
        lastSampleAt = nil
        lastHeight = nil
        previousHeightSample = nil
        speedMMps = 0
        movement = .stopped
        discovered = []
        controllerUsesStepCommands = false
        referenceInputFailures = 0
        appendLog(.info, demo ? "Demo mode enabled" : "Bluetooth mode enabled")
    }
}

extension HeightScale {
    public static func describe(_ mm: Double) -> String {
        String(format: "%.1f cm", mm / 10)
    }
}
