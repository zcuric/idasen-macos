import Foundation

/// A fully in-memory desk that mimics the LINAK BLE behaviour.
///
/// Used by the "Demo mode" setting so the app can be explored, and by unit
/// tests, without real hardware. It mirrors the real controller semantics:
/// movement commands only last while they keep arriving, and reference-input
/// moves stop once the target is reached.
@MainActor
public final class SimulatedDeskLink: DeskLink {
    public weak var delegate: DeskLinkDelegate?

    public var savedDeskID: UUID?
    public var connectedDeskName: String? { connected ? "Desk (simulated)" : nil }

    public private(set) var state: ConnectionState = .idle {
        didSet {
            guard state != oldValue else { return }
            delegate?.linkDidChangeState(self, state: state)
        }
    }

    /// Current simulated height in millimetres.
    public private(set) var heightMM: Double = 730
    /// Simulated cruise speed in mm/s; this is not a hardware speed setting.
    public var speedMMps: Double = 38
    /// Set to false to emulate controllers that ignore the reference input.
    public var supportsReferenceInput = true
    /// Commands recorded for controller regression tests.
    public private(set) var writtenCommands: [IdasenCommand] = []

    private var connected = false
    private var tickTimer: Timer?
    private var lastTickAt: Date?
    private var target: Double?
    private var freeDirection: MovementDirection = .stopped
    private var lastCommandAt: Date = .distantPast
    private var connectWorkItem: DispatchWorkItem?
    private var scanWorkItem: DispatchWorkItem?

    private let deskID = UUID(uuidString: "5EED0000-0000-4000-8000-00000000DE5C")!

    public init() {}

    // MARK: DeskLink

    public func startScan() {
        guard !connected else { return }
        state = .scanning
        scanWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.connected else { return }
            self.delegate?.link(
                self,
                didDiscover: DiscoveredDesk(id: self.deskID, name: "Desk 1904", rssi: -58, isIdasen: true)
            )
        }
        scanWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    public func stopScan() {
        scanWorkItem?.cancel()
        if case .scanning = state { state = .idle }
    }

    public func connect(to id: UUID, name: String) {
        connectSaved()
        _ = name
    }

    @discardableResult
    public func connectSaved() -> Bool {
        stopScan()
        state = .connecting(name: "Desk (simulated)")
        connectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.connected = true
            self.savedDeskID = self.deskID
            self.state = .connected(name: "Desk (simulated)")
            self.delegate?.linkDidBecomeReady(self)
            self.emit(height: self.heightMM, speed: 0)
            self.startTicking()
        }
        connectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        return true
    }

    public func disconnect() {
        connectWorkItem?.cancel()
        stopScan()
        tickTimer?.invalidate()
        tickTimer = nil
        connected = false
        target = nil
        freeDirection = .stopped
        state = .idle
    }

    public func forgetSaved() {
        disconnect()
        savedDeskID = nil
    }

    public func write(command: IdasenCommand) {
        guard connected else { return }
        if writtenCommands.count >= 512 { writtenCommands.removeFirst(128) }
        writtenCommands.append(command)
        switch command {
        case .up:
            freeDirection = .up
            target = nil
            lastCommandAt = Date()
        case .down:
            freeDirection = .down
            target = nil
            lastCommandAt = Date()
        case .stop:
            freeDirection = .stopped
            target = nil
        case .wakeUp:
            break
        }
    }

    public func writeReference(bytes: [UInt8]) {
        guard connected, bytes.count >= 2 else { return }
        if bytes == referenceInputStopBytes {
            target = nil
            freeDirection = .stopped
            emit(height: heightMM, speed: 0)
            return
        }
        guard supportsReferenceInput else { return }
        let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        let scale = HeightScale.idasen
        target = scale.millimeters(forRaw: raw)
        freeDirection = .stopped
        lastCommandAt = Date()
    }

    public func requestHeight() {
        guard connected else { return }
        emit(height: heightMM, speed: currentSpeed)
    }

    // MARK: Simulation

    private var currentSpeed: Double {
        if target != nil { return speedMMps }
        if freeDirection != .stopped { return speedMMps }
        return 0
    }

    private func startTicking() {
        tickTimer?.invalidate()
        lastTickAt = Date()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickOnce() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tickOnce() {
        let now = Date()
        let dt = min(max(now.timeIntervalSince(lastTickAt ?? now), 0.001), 0.2)
        lastTickAt = now
        tick(dt: dt)
    }

    private func tick(dt: Double) {
        guard connected else { return }
        let distance = speedMMps * dt

        if let target {
            let delta = target - heightMM
            if abs(delta) <= distance {
                heightMM = target
                self.target = nil
                emit(height: heightMM, speed: 0)
                return
            }
            heightMM += delta > 0 ? distance : -distance
            emit(height: heightMM, speed: delta > 0 ? speedMMps : -speedMMps)
            return
        }

        // Free movement requires a command at least every ~0.6 s, like the desk.
        guard freeDirection != .stopped, Date().timeIntervalSince(lastCommandAt) < 0.6 else {
            if freeDirection != .stopped {
                freeDirection = .stopped
                emit(height: heightMM, speed: 0)
            }
            return
        }

        let next = heightMM + (freeDirection == .up ? distance : -distance)
        heightMM = min(max(next, HeightScale.idasen.minimumMM), HeightScale.idasen.maximumMM)
        emit(height: heightMM, speed: freeDirection == .up ? speedMMps : -speedMMps)
    }

    private var sampleCounter = 0

    private func emit(height: Double, speed: Double) {
        sampleCounter += 1
        guard sampleCounter % 2 == 0 || speed == 0 else { return }
        let raw = HeightScale.idasen.rawUnits(forMillimeters: height)
        let sample = DeskHeightSample(raw: raw, speed: Int16(speed * 10))
        delegate?.link(self, didUpdate: sample)
    }
}
