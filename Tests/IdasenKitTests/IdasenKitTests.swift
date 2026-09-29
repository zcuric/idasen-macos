import XCTest
@testable import IdasenKit

final class IdasenProtocolTests: XCTestCase {
    func testCommandBytes() {
        XCTAssertEqual(IdasenCommand.up.bytes, [0x47, 0x00])
        XCTAssertEqual(IdasenCommand.down.bytes, [0x46, 0x00])
        XCTAssertEqual(IdasenCommand.stop.bytes, [0xFF, 0x00])
        XCTAssertEqual(IdasenCommand.wakeUp.bytes, [0xFE, 0x00])
        XCTAssertEqual(referenceInputStopBytes, [0x01, 0x80])
    }

    func testDecodeSample() throws {
        let sample = try XCTUnwrap(DeskHeightSample(data: Data([0x51, 0x04, 0x00, 0x00])))
        XCTAssertEqual(sample.raw, 0x0451)
        XCTAssertEqual(sample.speed, 0)
        XCTAssertFalse(sample.isMoving)
    }

    func testDecodeNegativeSpeed() throws {
        let sample = try XCTUnwrap(DeskHeightSample(data: Data([0x00, 0x10, 0xFF, 0xFF])))
        XCTAssertEqual(sample.raw, 0x1000)
        XCTAssertEqual(sample.speed, -1)
        XCTAssertTrue(sample.isMoving)
    }

    func testDecodeRejectsShortPayloads() {
        XCTAssertNil(DeskHeightSample(data: Data([0x01, 0x02])))
    }

    /// Values captured from a real IDÅSEN (see the `idasen` Rust crate doctests).
    func testRealWorldHeights() {
        let scale = HeightScale.idasen
        let cases: [(raw: UInt16, mm: Double)] = [
            (0x0000, 620.0),
            (1105, 730.5),
            (2056, 825.6),
            (6276, 1247.6),
            (6500, 1270.0),
        ]
        for entry in cases {
            XCTAssertEqual(scale.millimeters(forRaw: entry.raw), entry.mm, accuracy: 0.001)
        }
    }

    func testRawRoundTrip() {
        let scale = HeightScale.idasen
        for mm in stride(from: 620.0, through: 1270.0, by: 7.3) {
            let raw = scale.rawUnits(forMillimeters: mm)
            XCTAssertEqual(scale.millimeters(forRaw: raw), mm, accuracy: 0.1)
        }
    }

    func testReferenceInputEncoding() {
        let scale = HeightScale.idasen
        XCTAssertEqual(scale.referenceInputBytes(forMillimeters: 1270), [0x64, 0x19])
        XCTAssertEqual(scale.referenceInputBytes(forMillimeters: 620), [0x00, 0x00])
        XCTAssertEqual(scale.referenceInputBytes(forMillimeters: 730.5), [0x51, 0x04])
    }

    func testRawClamping() {
        let scale = HeightScale.idasen
        XCTAssertEqual(scale.rawUnits(forMillimeters: 100), 0)
        XCTAssertEqual(scale.rawUnits(forMillimeters: 10_000), 65_535)
    }

    func testWrapAroundBelowZeroPoint() {
        let scale = HeightScale.idasen
        // A desk calibrated lower than the assumed zero point wraps the raw value.
        let wrapped = UInt16(bitPattern: Int16(-200))
        XCTAssertEqual(scale.millimeters(forRaw: wrapped), 600.0, accuracy: 0.001)
    }

    func testClampAndContains() {
        let scale = HeightScale.idasen
        XCTAssertEqual(scale.clamp(500), 620)
        XCTAssertEqual(scale.clamp(1500), 1270)
        XCTAssertTrue(scale.contains(1000))
        XCTAssertFalse(scale.contains(1290))
    }

    func testFraction() {
        let scale = HeightScale.idasen
        XCTAssertEqual(scale.fraction(forMillimeters: 620), 0, accuracy: 0.0001)
        XCTAssertEqual(scale.fraction(forMillimeters: 945), 0.5, accuracy: 0.0001)
        XCTAssertEqual(scale.fraction(forMillimeters: 1270), 1, accuracy: 0.0001)
    }

    func testUnitConversion() {
        XCTAssertEqual(LengthUnit.centimeters.value(fromMillimeters: 730), 73, accuracy: 0.001)
        XCTAssertEqual(LengthUnit.inches.value(fromMillimeters: 730), 28.74, accuracy: 0.01)
        XCTAssertEqual(LengthUnit.inches.millimeters(fromValue: 30), 762, accuracy: 0.001)
        XCTAssertEqual(LengthUnit.centimeters.format(millimeters: 730), "73.0 cm")
        XCTAssertEqual(LengthUnit.inches.format(millimeters: 730), "28.7 in")
    }

    func testHeightScaleCodable() throws {
        let scale = HeightScale(offsetMM: 600, minimumMM: 600, maximumMM: 1280)
        let data = try JSONEncoder().encode(scale)
        let decoded = try JSONDecoder().decode(HeightScale.self, from: data)
        XCTAssertEqual(decoded, scale)
    }

    func testMoveProgressFraction() {
        let progress = MoveProgress(targetMM: 1100, startMM: 700, currentMM: 900)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.0001)
        let done = MoveProgress(targetMM: 1100, startMM: 700, currentMM: 1100)
        XCTAssertEqual(done.fraction, 1, accuracy: 0.0001)
    }
}

@MainActor
final class DeskServiceTests: XCTestCase {
    private func makeSettings(demo: Bool = true) -> AppSettings {
        var settings = AppSettings()
        settings.demoMode = demo
        settings.autoConnect = false
        settings.reconnectAutomatically = false
        settings.warmUpBeforeMoves = false
        return settings
    }

    func testReferenceArrivalWaitsForControllerStoppedSignal() async throws {
        let service = DeskService(settings: makeSettings())
        let link = service.simulatedLinkForTesting
        // Inject telemetry without starting the simulator's timer.
        service.linkDidChangeState(link, state: .connected(name: "Test desk"))
        service.linkDidBecomeReady(link)
        let start = Date()
        func sample(_ height: Double, _ speed: Int16, _ offset: Double) {
            service.link(link, didUpdate: DeskHeightSample(
                raw: HeightScale.idasen.rawUnits(forMillimeters: height), speed: speed,
                receivedAt: start.addingTimeInterval(offset)
            ))
        }
        sample(730, 0, 0)
        service.go(toMM: 735)
        sample(734, 1, 0.1)
        sample(734.1, 1, 0.2)
        sample(734.2, 1, 0.3)
        XCTAssertLessThan(service.speedMMps, 8)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNotNil(service.progress, "Do not interrupt the controller's slow final approach")
        sample(734.2, 0, 0.4)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(service.progress)
        XCTAssertNil(service.lastError)
    }

    func testSameDirectionRetargetKeepsPositionMoveContinuous() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await Task.sleep(for: .milliseconds(700))
        service.go(toMM: 1000)
        try await Task.sleep(for: .milliseconds(300))
        let stopsBefore = service.simulatedLinkForTesting.writtenCommands.filter { $0 == .stop }.count
        service.go(toMM: 1100)
        let stopsAfter = service.simulatedLinkForTesting.writtenCommands.filter { $0 == .stop }.count
        XCTAssertEqual(stopsAfter, stopsBefore)
        XCTAssertEqual(service.progress?.targetMM, 1100)
        service.stop()
        service.disconnect()
    }

    func testRetargetingToCurrentHeightStopsAnActiveHold() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await Task.sleep(for: .milliseconds(700))
        service.startHold(.up)
        let current = try XCTUnwrap(service.heightMM)
        service.go(toMM: current)
        XCTAssertEqual(service.holdingDirection, .stopped)
        XCTAssertEqual(service.simulatedLinkForTesting.writtenCommands.last, .stop)
        service.disconnect()
    }

    func testDuplicateTelemetryDoesNotZeroMovementSpeed() {
        let service = DeskService(settings: makeSettings())
        let link = service.simulatedLinkForTesting
        let start = Date()
        for (offset, height) in [(0.0, 730.0), (0.1, 734.0), (0.101, 734.0)] {
            service.link(link, didUpdate: DeskHeightSample(
                raw: HeightScale.idasen.rawUnits(forMillimeters: height),
                speed: 500,
                receivedAt: start.addingTimeInterval(offset)
            ))
        }
        XCTAssertGreaterThan(service.speedMMps, 10)
    }

    func testMovementSpeedUsesPositionSamples() {
        let service = DeskService(settings: makeSettings())
        let link = service.simulatedLinkForTesting
        let start = Date()
        let scale = HeightScale.idasen

        service.link(link, didUpdate: DeskHeightSample(
            raw: scale.rawUnits(forMillimeters: 730),
            speed: 30_000,
            receivedAt: start
        ))
        service.link(link, didUpdate: DeskHeightSample(
            raw: scale.rawUnits(forMillimeters: 734),
            speed: 30_000,
            receivedAt: start.addingTimeInterval(0.1)
        ))

        XCTAssertGreaterThan(service.speedMMps, 10)
        XCTAssertLessThan(service.speedMMps, 20)

        service.link(link, didUpdate: DeskHeightSample(
            raw: scale.rawUnits(forMillimeters: 734),
            speed: 0,
            receivedAt: start.addingTimeInterval(0.2)
        ))
        XCTAssertEqual(service.speedMMps, 0)
    }

    func testHoldStopsAtSafetyTimeout() async throws {
        var settings = makeSettings()
        settings.safetyMaxRunSeconds = 0.3
        let service = DeskService(settings: settings)
        XCTAssertTrue(service.connectSavedDesk())
        try await waitFor(timeout: 2) { service.isConnected && service.heightMM != nil }

        service.startHold(.up)
        try await waitFor(timeout: 1) { service.holdingDirection == .stopped }
        XCTAssertEqual(service.lastError, .moveTimeout)
    }

    func testConnectAndReadHeight() async throws {
        let service = DeskService(settings: makeSettings())
        XCTAssertFalse(service.isConnected)

        XCTAssertTrue(service.connectSavedDesk())

        let connected = expectation(description: "connected")
        var attempts = 0
        while !service.isConnected && attempts < 100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
        if service.isConnected { connected.fulfill() }
        await fulfillment(of: [connected], timeout: 2)

        XCTAssertNotNil(service.heightMM)
        XCTAssertEqual(service.heightMM ?? 0, 730, accuracy: 1)
    }

    func testMoveToTargetArrives() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.go(toMM: 800)
        try await waitFor(timeout: 6) { service.progress == nil && abs((service.heightMM ?? 0) - 800) < 6 }
        XCTAssertEqual(service.heightMM ?? 0, 800, accuracy: 6)
    }

    func testStopDuringMove() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.go(toMM: 1200)
        try await Task.sleep(nanoseconds: 500_000_000)
        service.stop()
        let stoppedAt = service.heightMM ?? 0
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(service.heightMM ?? 0, stoppedAt, accuracy: 3)
        XCTAssertNil(service.progress)
    }

    func testHoldMovesUntilReleased() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        let start = service.heightMM ?? 0
        service.startHold(.up)
        try await Task.sleep(nanoseconds: 700_000_000)
        service.endHold()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(service.heightMM ?? 0, start + 5)
    }

    func testRepeatedHoldPressDoesNotRestartMovementLoop() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.startHold(.up)
        service.startHold(.up)
        XCTAssertEqual(service.log.filter { $0.message == "Raising (held)" }.count, 1)
        service.endHold()
    }

    /// Some controllers ignore the reference-input channel; the service must
    /// fall back to raise/lower commands and still land close to the target.
    func testFallsBackToStepCommandsWhenReferenceInputIsIgnored() async throws {
        let service = DeskService(settings: makeSettings())
        let link = service.simulatedLinkForTesting
        link.supportsReferenceInput = false
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.go(toMM: 830)
        try await waitFor(timeout: 20) {
            service.progress == nil && abs((service.heightMM ?? 0) - 830) < 20
        }
        XCTAssertEqual(service.heightMM ?? 0, 830, accuracy: 8)
        XCTAssertTrue(service.log.contains { $0.message.contains("raise/lower commands") })
        XCTAssertLessThanOrEqual(link.writtenCommands.filter { $0 == .stop }.count, 2,
                                 "A target move should settle without repeated stop/start bursts")
    }

    func testOneReferenceInputFailureDoesNotDisableFuturePositionMoves() async throws {
        let service = DeskService(settings: makeSettings())
        let link = service.simulatedLinkForTesting
        link.supportsReferenceInput = false
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.go(toMM: 810)
        try await waitFor(timeout: 12) { service.progress == nil && abs((service.heightMM ?? 0) - 810) < 8 }

        let stepCommands = link.writtenCommands.filter { $0 == .up || $0 == .down }.count
        link.supportsReferenceInput = true
        service.go(toMM: 900)
        try await waitFor(timeout: 12) { service.progress == nil && abs((service.heightMM ?? 0) - 900) < 8 }

        XCTAssertEqual(link.writtenCommands.filter { $0 == .up || $0 == .down }.count, stepCommands,
                       "A single failed probe should not permanently force step commands")
    }

    func testSlowDownwardFallbackSettlesWithoutRepeatedCorrections() async throws {
        let service = DeskService(settings: makeSettings())
        let link = service.simulatedLinkForTesting
        link.supportsReferenceInput = false
        link.speedMMps = 18
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.go(toMM: 650)
        try await waitFor(timeout: 12) { service.progress == nil && abs((service.heightMM ?? 0) - 650) < 8 }

        XCTAssertEqual(service.heightMM ?? 0, 650, accuracy: 8)
        XCTAssertLessThanOrEqual(link.writtenCommands.filter { $0 == .stop }.count, 2)
    }

    func testMovingDown() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.go(toMM: 1150)
        try await waitFor(timeout: 20) { abs((service.heightMM ?? 0) - 1150) < 6 }
        service.go(toMM: 700)
        try await waitFor(timeout: 20) {
            service.progress == nil && abs((service.heightMM ?? 0) - 700) < 6
        }
        XCTAssertEqual(service.heightMM ?? 0, 700, accuracy: 6)
    }

    func testRejectsOutOfRangeTarget() async throws {
        let service = DeskService(settings: makeSettings())
        service.connectSavedDesk()
        try await waitFor { service.isConnected }

        service.go(toMM: 2000)
        XCTAssertEqual(service.lastError, .invalidTarget)
        XCTAssertNil(service.progress)
    }

    private func waitFor(
        timeout: TimeInterval = 3,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met within \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 40_000_000)
        }
    }
}

@MainActor
final class ActivityRecorderTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idasen-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRecordingCreatesSegments() {
        let recorder = ActivityRecorder(directory: directory)
        let start = Date()
        recorder.record(heightMM: 730, at: start, thresholdMM: 900)
        recorder.record(heightMM: 730, at: start.addingTimeInterval(30), thresholdMM: 900)
        recorder.record(heightMM: 1100, at: start.addingTimeInterval(60), thresholdMM: 900)
        recorder.record(heightMM: 1100, at: start.addingTimeInterval(120), thresholdMM: 900)

        XCTAssertEqual(recorder.today.segments.count, 2)
        XCTAssertEqual(recorder.today.transitions, 1)
        XCTAssertEqual(recorder.today.sittingSeconds, 60, accuracy: 0.5)
        XCTAssertEqual(recorder.today.standingSeconds, 60, accuracy: 0.5)
        XCTAssertEqual(recorder.today.minMM, 730)
        XCTAssertEqual(recorder.today.maxMM, 1100)
    }

    func testShortBlipsAreFolded() {
        let recorder = ActivityRecorder(directory: directory)
        let start = Date()
        recorder.record(heightMM: 730, at: start, thresholdMM: 900)
        recorder.record(heightMM: 730, at: start.addingTimeInterval(20), thresholdMM: 900)
        // A 2 s standing blip should not create a transition.
        recorder.record(heightMM: 1100, at: start.addingTimeInterval(22), thresholdMM: 900)
        recorder.record(heightMM: 730, at: start.addingTimeInterval(24), thresholdMM: 900)
        recorder.record(heightMM: 730, at: start.addingTimeInterval(40), thresholdMM: 900)

        XCTAssertEqual(recorder.today.segments.count, 1)
        XCTAssertEqual(recorder.today.transitions, 0)
        XCTAssertEqual(recorder.today.sittingSeconds, 40, accuracy: 0.5)
    }

    func testStandingRatioAndStreak() {
        var day = DayActivity(day: Date())
        day.segments = [
            ActivitySegment(start: Date(), end: Date().addingTimeInterval(60), state: .sitting),
            ActivitySegment(start: Date(), end: Date().addingTimeInterval(180), state: .standing),
        ]
        XCTAssertEqual(day.standingSeconds, 180, accuracy: 0.1)
        XCTAssertEqual(day.standingRatio, 0.75, accuracy: 0.001)
        XCTAssertEqual(day.longestStandingStreak, 180, accuracy: 0.1)
    }

    func testPersistenceSurvivesReload() {
        let recorder = ActivityRecorder(directory: directory)
        let start = Date()
        recorder.record(heightMM: 1100, at: start, thresholdMM: 900)
        recorder.record(heightMM: 1100, at: start.addingTimeInterval(120), thresholdMM: 900)
        recorder.persist()

        let reloaded = ActivityRecorder(directory: directory)
        XCTAssertEqual(reloaded.today.standingSeconds, 120, accuracy: 1)
        XCTAssertEqual(reloaded.recentDays(1).count, 1)
    }

    func testExportCSV() {
        let recorder = ActivityRecorder(directory: directory)
        recorder.record(heightMM: 1100, at: Date(), thresholdMM: 900)
        let csv = recorder.exportCSV()
        XCTAssertTrue(csv.hasPrefix("date,start,end,state,duration_minutes"))
        XCTAssertTrue(csv.contains("standing"))
    }
}

@MainActor
final class PresetStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("idasen-preset-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDefaults() {
        let store = PresetStore(directory: directory)
        XCTAssertEqual(store.presets.count, 2)
        XCTAssertNotNil(store.sitPreset)
        XCTAssertNotNil(store.standPreset)
        XCTAssertLessThan(store.sitPreset!.heightMM, store.standPreset!.heightMM)
    }

    func testAddUpdateRemove() {
        let store = PresetStore(directory: directory)
        let preset = DeskPreset(name: "Focus", heightMM: 1050)
        store.add(preset)
        XCTAssertEqual(store.presets.count, 3)

        var edited = preset
        edited.name = "Deep Focus"
        store.update(edited)
        XCTAssertEqual(store.presets.last?.name, "Deep Focus")

        store.remove(id: preset.id)
        XCTAssertEqual(store.presets.count, 2)
    }

    func testMarkSitAndStand() {
        let store = PresetStore(directory: directory)
        let extra = DeskPreset(name: "Custom", heightMM: 900)
        store.add(extra)
        store.markSit(extra.id)
        XCTAssertEqual(store.sitPreset?.id, extra.id)
        store.markStand(extra.id)
        XCTAssertEqual(store.standPreset?.id, extra.id)
    }

    func testRoundTrip() {
        let store = PresetStore(directory: directory)
        store.add(DeskPreset(name: "Reading", heightMM: 1150))
        let reloaded = PresetStore(directory: directory)
        XCTAssertEqual(reloaded.presets.count, 3)
        XCTAssertTrue(reloaded.presets.contains { $0.name == "Reading" })
    }
}

final class AppSettingsTests: XCTestCase {
    func testRapidEditsPersistLatestValueWhenFlushed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("idasen-settings-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SettingsStore(directory: directory)
        store.settings.dailyStandingGoalMinutes = 90
        store.settings.dailyStandingGoalMinutes = 105
        store.settings.dailyStandingGoalMinutes = 120
        store.flushPendingSave()

        XCTAssertEqual(SettingsStore(directory: directory).settings.dailyStandingGoalMinutes, 120)
    }

    func testSitStandThresholdAuto() {
        var settings = AppSettings()
        XCTAssertEqual(settings.sitStandThreshold(sitMM: 730, standMM: 1100), 915)
        settings.sitStandThresholdMM = 950
        XCTAssertEqual(settings.sitStandThreshold(sitMM: 730, standMM: 1100), 950)
        settings.sitStandThresholdMM = 0
        XCTAssertEqual(settings.sitStandThreshold(sitMM: nil, standMM: nil), 960)
    }

    func testSettingsDecodeWithMissingKeys() throws {
        let json = #"{"unit":"inches","demoMode":true}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.unit, .inches)
        XCTAssertTrue(settings.demoMode)
        XCTAssertTrue(settings.autoConnect)
        XCTAssertFalse(settings.menuBarOnly)
    }

    func testMenuBarOnlySettingPersists() throws {
        var settings = AppSettings()
        settings.menuBarOnly = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.menuBarOnly)
        XCTAssertTrue(decoded.showMenuBarExtra)
    }

    func testHotKeyDisplay() {
        let combo = HotKeyCombo(
            keyCode: 0x7E,
            modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue
        )
        XCTAssertEqual(combo.displayString, "⌃⌥↑")
    }
}

@MainActor
final class AppFlowTests: XCTestCase {
    func testSwitchingToDemoModeThenConnecting() async throws {
        var settings = AppSettings()
        settings.autoConnect = true
        let service = DeskService(settings: settings)
        XCTAssertEqual(service.settings.demoMode, false)

        settings.demoMode = true
        settings.lastDeskID = UUID()
        service.settings = settings

        XCTAssertTrue(service.connectSavedDesk())
        let deadline = Date().addingTimeInterval(3)
        while !service.isConnected && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(service.isConnected, "state: \(service.connection)")
        XCTAssertNotNil(service.heightMM)
    }
}
