import Foundation

/// Bounded pending BLE work. A command already handed to CoreBluetooth cannot
/// be recalled; unsent motion is always replaced by the latest intent.
struct DeskWriteBuffer {
    enum Operation: Equatable {
        case command(IdasenCommand)
        case reference([UInt8])
        case dpg([UInt8])

        var isMotion: Bool {
            switch self {
            case .command(.up), .command(.down): true
            case .reference(let bytes): bytes != referenceInputStopBytes
            default: false
            }
        }

        var isStop: Bool {
            self == .command(.stop) || self == .reference(referenceInputStopBytes)
        }
    }

    struct Entry {
        let operation: Operation
        let enqueuedAt: TimeInterval
    }

    private(set) var entries: [Entry] = []

    mutating func enqueue(_ operation: Operation, at time: TimeInterval) {
        // Never replay a queued direction/target after a release or new intent.
        if operation.isMotion || operation.isStop {
            entries.removeAll { $0.operation.isMotion }
        }
        entries.removeAll { $0.operation == operation }
        entries.append(Entry(operation: operation, enqueuedAt: time))
    }

    mutating func next(at time: TimeInterval) -> Operation? {
        // A delayed press must not start the desk after its input has gone stale.
        entries.removeAll { !$0.operation.isStop && time - $0.enqueuedAt > 0.5 }
        return entries.first?.operation
    }

    mutating func removeFirst() { if !entries.isEmpty { entries.removeFirst() } }
    mutating func reset() { entries.removeAll(keepingCapacity: true) }
}
