import CoreBluetooth
import Foundation

/// GATT identifiers used by the IKEA IDÅSEN desk (LINAK controller).
///
/// The desk is not pairable; everything happens over an unencrypted BLE GATT
/// connection. All UUIDs share the base `338a-1024-8a49-009c0215f78a`.
@MainActor
public enum IdasenUUID {
    /// Service advertised by the desk. Used to recognize desks while scanning.
    public static let advertisedService = CBUUID(string: "99FA0001-338A-1024-8A49-009C0215F78A")
    /// Write-only characteristic that accepts movement commands.
    public static let command = CBUUID(string: "99FA0002-338A-1024-8A49-009C0215F78A")
    /// Notifies the movement state of the controller.
    public static let commandStatus = CBUUID(string: "99FA0003-338A-1024-8A49-009C0215F78A")
    /// LINAK DPG (handset) input characteristic, used by some controllers.
    public static let dpgInput = CBUUID(string: "99FA0011-338A-1024-8A49-009C0215F78A")
    /// Notifies `[height: uint16 LE][speed: int16 LE]`, every 0.1 mm / unit.
    public static let height = CBUUID(string: "99FA0021-338A-1024-8A49-009C0215F78A")
    /// Write-only "reference input" used to drive the desk to an absolute height.
    public static let referenceInput = CBUUID(string: "99FA0031-338A-1024-8A49-009C0215F78A")
}

/// Commands that can be written to ``IdasenUUID/command``.
public enum IdasenCommand: String, CaseIterable, Sendable, Codable {
    case up
    case down
    case stop
    /// Wakes a sleeping controller. Also required once before reference input moves.
    case wakeUp

    public var bytes: [UInt8] {
        switch self {
        case .up: return [0x47, 0x00]
        case .down: return [0x46, 0x00]
        case .stop: return [0xFF, 0x00]
        case .wakeUp: return [0xFE, 0x00]
        }
    }

    public var title: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .stop: return "Stop"
        case .wakeUp: return "Wake up"
        }
    }
}

/// Bytes written to ``IdasenUUID/referenceInput`` to abort an in-flight move.
public let referenceInputStopBytes: [UInt8] = [0x01, 0x80]

/// A raw notification/read from the height characteristic.
///
/// * `raw` is the desk position in units of 0.1 mm, relative to the desk's
///   calibrated zero point (see ``HeightScale/offsetMM``).
/// * `speed` is signed and negative while the desk travels down on most
///   controllers, but the unit is not documented. It is used only to detect
///   movement, never for absolute math.
public struct DeskHeightSample: Equatable, Sendable, Codable {
    public var raw: UInt16
    public var speed: Int16
    /// When the sample was received (not persisted meaningfully).
    public var receivedAt: Date

    public init(raw: UInt16, speed: Int16, receivedAt: Date = Date()) {
        self.raw = raw
        self.speed = speed
        self.receivedAt = receivedAt
    }

    /// Decodes the 4-byte little-endian payload of the height characteristic.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        let speed = Int16(bitPattern: UInt16(bytes[2]) | (UInt16(bytes[3]) << 8))
        self.init(raw: raw, speed: speed)
    }

    public var isMoving: Bool { speed != 0 }
}

/// Describes the physical desk and how raw controller units map to millimetres.
///
/// The controller reports positions relative to a zero point that is assumed to
/// be 62 cm above the floor (the IDÅSEN's nominal minimum). If a particular
/// desk has been re-calibrated, the value can be corrected with
/// ``offsetMM`` (see the height calibration flow in the app).
public struct HeightScale: Equatable, Sendable, Codable {
    /// Height of the controller's zero point above the floor, in millimetres.
    public var offsetMM: Double
    /// Soft lower bound used by the UI and for validating targets.
    public var minimumMM: Double
    /// Soft upper bound used by the UI and for validating targets.
    public var maximumMM: Double

    public static let idasen = HeightScale(offsetMM: 620, minimumMM: 620, maximumMM: 1270)

    public init(offsetMM: Double = 620, minimumMM: Double = 620, maximumMM: Double = 1270) {
        self.offsetMM = offsetMM
        self.minimumMM = minimumMM
        self.maximumMM = maximumMM
    }

    /// Converts a raw controller position into an absolute height.
    public func millimeters(forRaw raw: UInt16) -> Double {
        // Guard against wrap-around for desks calibrated below the zero point.
        if raw > 20_000 {
            return offsetMM + (Double(raw) - 65_536) / 10
        }
        return offsetMM + Double(raw) / 10
    }

    /// Inverse of ``millimeters(forRaw:)``, clamped to the encodable range.
    public func rawUnits(forMillimeters mm: Double) -> UInt16 {
        let units = ((mm - offsetMM) * 10).rounded()
        return UInt16(max(0, min(65_535, units)))
    }

    /// Encodes a target height for the reference-input characteristic.
    public func referenceInputBytes(forMillimeters mm: Double) -> [UInt8] {
        let units = rawUnits(forMillimeters: mm)
        return [UInt8(units & 0xFF), UInt8(units >> 8)]
    }

    public func clamp(_ mm: Double) -> Double {
        min(max(mm, minimumMM), maximumMM)
    }

    public func contains(_ mm: Double) -> Bool {
        mm >= minimumMM && mm <= maximumMM
    }

    /// Fraction (0...1) of the travel range for a height.
    public func fraction(forMillimeters mm: Double) -> Double {
        guard maximumMM > minimumMM else { return 0 }
        return Swift.min(Swift.max((mm - minimumMM) / (maximumMM - minimumMM), 0), 1)
    }
}
