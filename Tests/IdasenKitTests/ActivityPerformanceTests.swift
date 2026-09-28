import Combine
import XCTest
@testable import IdasenKit

@MainActor
final class ActivityPerformanceTests: XCTestCase {
    func testHighRateSamplesKeepAccurateHistoryWithoutRedrawingEveryPacket() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = ActivityRecorder(directory: directory)
        var updates = 0
        let subscription = recorder.objectWillChange.sink { updates += 1 }
        let start = Date()
        for index in 0..<100 {
            recorder.record(heightMM: 730, at: start.addingTimeInterval(Double(index) / 100), thresholdMM: 960)
        }
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(recorder.today.sittingSeconds, 0.99, accuracy: 0.001)
        recorder.persist()
        let reloaded = ActivityRecorder(directory: directory)
        XCTAssertEqual(reloaded.today.segments.count, 1)
        XCTAssertEqual(reloaded.today.samples.first?.heightMM, 730)
        withExtendedLifetime(subscription) {}
    }
}
