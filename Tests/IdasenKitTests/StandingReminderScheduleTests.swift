import XCTest
@testable import IdasenKit

final class StandingReminderScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testContinuousTelemetryDoesNotDelayReminderAndDeliveryDoesNotRepeat() {
        var schedule = StandingReminderSchedule()
        for second in 0..<2700 {
            XCTAssertFalse(due(&schedule, Double(second)))
        }
        XCTAssertTrue(due(&schedule, 2700))
        XCTAssertFalse(due(&schedule, 2720))
        XCTAssertTrue(due(&schedule, 5400))
    }

    func testSnoozeIsTenMinutesRatherThanConfiguredInterval() {
        var schedule = StandingReminderSchedule()
        XCTAssertFalse(due(&schedule, 0))
        XCTAssertTrue(due(&schedule, 2700))
        schedule.snooze(at: start.addingTimeInterval(2710))
        XCTAssertFalse(due(&schedule, 3309))
        XCTAssertTrue(due(&schedule, 3310))
    }

    func testStandingDisconnectAndDisableResetSittingInterval() {
        for resetMode in 0..<3 {
            var schedule = StandingReminderSchedule()
            XCTAssertFalse(due(&schedule, 0))
            XCTAssertFalse(schedule.isDue(at: start.addingTimeInterval(2600), enabled: resetMode != 0,
                connected: resetMode != 1, moving: false, sittingSince: resetMode == 2 ? nil : start,
                onlyWhileSitting: true, intervalMinutes: 45))
            XCTAssertFalse(due(&schedule, 2700))
            XCTAssertTrue(due(&schedule, 5400))
        }
    }

    func testMovementDefersReminderUntilDeskStops() {
        var schedule = StandingReminderSchedule()
        XCTAssertFalse(due(&schedule, 0))
        XCTAssertFalse(due(&schedule, 2700, moving: true))
        XCTAssertTrue(due(&schedule, 2720))
    }

    func testAllPosturesModeHasStableInitialDeadline() {
        var schedule = StandingReminderSchedule()
        XCTAssertFalse(due(&schedule, 0, onlySitting: false))
        XCTAssertTrue(due(&schedule, 2700, onlySitting: false))
    }

    func testNewSittingSessionStartsFreshInterval() {
        var schedule = StandingReminderSchedule()
        XCTAssertFalse(due(&schedule, 0))
        XCTAssertFalse(schedule.isDue(at: start.addingTimeInterval(2600), enabled: true, connected: true,
            moving: false, sittingSince: start.addingTimeInterval(2500), onlyWhileSitting: true, intervalMinutes: 45))
        XCTAssertFalse(schedule.isDue(at: start.addingTimeInterval(2700), enabled: true, connected: true,
            moving: false, sittingSince: start.addingTimeInterval(2500), onlyWhileSitting: true, intervalMinutes: 45))
    }

    private func due(_ schedule: inout StandingReminderSchedule, _ seconds: Double,
                     moving: Bool = false, onlySitting: Bool = true) -> Bool {
        schedule.isDue(at: start.addingTimeInterval(seconds), enabled: true, connected: true,
            moving: moving, sittingSince: onlySitting ? start : nil, onlyWhileSitting: onlySitting, intervalMinutes: 45)
    }
}
