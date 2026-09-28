import XCTest
@testable import IdasenKit

final class DeskWriteBufferTests: XCTestCase {
    func testReleaseDiscardsUnsentMotionOnBothChannels() {
        var buffer = DeskWriteBuffer()
        buffer.enqueue(.command(.up), at: 0)
        buffer.enqueue(.reference([0x10, 0x10]), at: 0.1)
        buffer.enqueue(.command(.stop), at: 0.2)
        buffer.enqueue(.reference(referenceInputStopBytes), at: 0.2)
        XCTAssertEqual(buffer.next(at: 0.3), .command(.stop))
        buffer.removeFirst()
        XCTAssertEqual(buffer.next(at: 0.3), .reference(referenceInputStopBytes))
        buffer.removeFirst()
        XCTAssertNil(buffer.next(at: 0.3))
    }

    func testPressureKeepsLatestDirectionAndPreflightOrder() {
        var buffer = DeskWriteBuffer()
        buffer.enqueue(.command(.wakeUp), at: 0)
        buffer.enqueue(.command(.stop), at: 0)
        for _ in 0..<100 { buffer.enqueue(.command(.up), at: 0.1) }
        buffer.enqueue(.command(.down), at: 0.2)
        XCTAssertEqual(buffer.entries.count, 3)
        XCTAssertEqual(buffer.next(at: 0.3), .command(.wakeUp))
        buffer.removeFirst()
        XCTAssertEqual(buffer.next(at: 0.3), .command(.stop))
        buffer.removeFirst()
        XCTAssertEqual(buffer.next(at: 0.3), .command(.down))
    }

    func testMotionExpiresButStopDoesNot() {
        var buffer = DeskWriteBuffer()
        buffer.enqueue(.command(.stop), at: 0)
        buffer.enqueue(.command(.up), at: 0)
        XCTAssertEqual(buffer.next(at: 3), .command(.stop))
        buffer.removeFirst()
        XCTAssertNil(buffer.next(at: 3))
    }
}
