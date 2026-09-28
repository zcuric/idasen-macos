import Foundation

// MARK: - Units

public enum LengthUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case centimeters
    case inches

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .centimeters: return "Centimetres"
        case .inches: return "Inches"
        }
    }

    public var shortTitle: String {
        switch self {
        case .centimeters: return "cm"
        case .inches: return "in"
        }
    }

    public var decimals: Int {
        switch self {
        case .centimeters: return 1
        case .inches: return 1
        }
    }

    /// Converts millimetres into the value displayed for this unit.
    public func value(fromMillimeters mm: Double) -> Double {
        switch self {
        case .centimeters: return mm / 10
        case .inches: return mm / 25.4
        }
    }

    /// Converts a value in this unit back to millimetres.
    public func millimeters(fromValue value: Double) -> Double {
        switch self {
        case .centimeters: return value * 10
        case .inches: return value * 25.4
        }
    }

    public func format(millimeters mm: Double, showUnit: Bool = true) -> String {
        let value = value(fromMillimeters: mm)
        let rounded = (value * 10).rounded() / 10
        var text = String(format: "%.\(decimals)f", rounded)
        if text.hasPrefix("-") { text = text.replacingOccurrences(of: "-0", with: "-") }
        return showUnit ? "\(text) \(shortTitle)" : text
    }
}

// MARK: - Movement

public enum MovementDirection: String, Codable, Sendable, Equatable {
    case up
    case down
    case stopped

    public var title: String {
        switch self {
        case .up: return "Moving up"
        case .down: return "Moving down"
        case .stopped: return "Idle"
        }
    }

    public var symbolName: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .stopped: return "pause.fill"
        }
    }

    public var opposite: MovementDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .stopped: return .stopped
        }
    }
}

public enum SitStandState: String, Codable, Sendable {
    case sitting
    case standing
    case unknown

    public var title: String {
        switch self {
        case .sitting: return "Sitting"
        case .standing: return "Standing"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Presets

public struct DeskPreset: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var heightMM: Double
    public var symbolName: String
    public var isSitPreset: Bool
    public var isStandPreset: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        heightMM: Double,
        symbolName: String = "bookmark.fill",
        isSitPreset: Bool = false,
        isStandPreset: Bool = false
    ) {
        self.id = id
        self.name = name
        self.heightMM = heightMM
        self.symbolName = symbolName
        self.isSitPreset = isSitPreset
        self.isStandPreset = isStandPreset
    }

    public var sitStand: SitStandState {
        if isSitPreset { return .sitting }
        if isStandPreset { return .standing }
        return .unknown
    }

    public static func `default`(scale: HeightScale = .idasen, unit: LengthUnit = .centimeters) -> [DeskPreset] {
        [
            DeskPreset(
                name: "Sit",
                heightMM: unit.millimeters(fromValue: unit == .centimeters ? 73 : 29),
                symbolName: "chair.lounge.fill",
                isSitPreset: true
            ),
            DeskPreset(
                name: "Stand",
                heightMM: unit.millimeters(fromValue: unit == .centimeters ? 110 : 43.5),
                symbolName: "figure.stand",
                isStandPreset: true
            ),
        ]
    }

    public var symbolCandidates: [String] {
        [
            "chair.lounge.fill", "figure.stand", "figure.walk", "figure.run",
            "desktopcomputer", "keyboard.fill", "laptopcomputer", "book.fill",
            "cup.and.saucer.fill", "moon.stars.fill", "sun.max.fill", "star.fill",
            "bookmark.fill", "arrow.up.arrow.down", "bicycle", "gamecontroller.fill",
            "music.note", "phone.fill", "paintbrush.fill", "leaf.fill",
        ]
    }
}

// MARK: - Errors

public enum DeskError: LocalizedError, Equatable {
    case bluetoothUnavailable(String)
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case deskNotFound
    case connectionFailed(String)
    case connectionLost
    case characteristicMissing
    case notConnected
    case invalidTarget
    case moveTimeout
    case moveStalled
    case moveBlocked
    case deskBusy

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let reason):
            return "Bluetooth is unavailable: \(reason)"
        case .bluetoothUnauthorized:
            return "Bluetooth access was denied. Allow Idasen in System Settings › Privacy & Security › Bluetooth."
        case .bluetoothPoweredOff:
            return "Bluetooth is turned off."
        case .deskNotFound:
            return "The desk could not be found. Press a button on the desk to wake it, then try again."
        case .connectionFailed(let reason):
            return "Could not connect to the desk. \(reason)"
        case .connectionLost:
            return "The connection to the desk was lost."
        case .characteristicMissing:
            return "The desk does not expose the expected control characteristics."
        case .notConnected:
            return "Not connected to a desk."
        case .invalidTarget:
            return "That height is outside the configured range."
        case .moveTimeout:
            return "Movement timed out and was stopped."
        case .moveStalled:
            return "The desk stopped before reaching the target."
        case .moveBlocked:
            return "Movement stopped — the desk's collision safety feature may have triggered."
        case .deskBusy:
            return "The desk is already moving."
        }
    }
}

// MARK: - Movement plan

/// Result of an automatic move to a height.
public enum MoveOutcome: Equatable {
    case arrived
    case cancelled
    case failed(DeskError)
}

/// State of an automatic move, exposed to the UI for progress display.
public struct MoveProgress: Equatable, Sendable {
    public var targetMM: Double
    public var startMM: Double
    public var currentMM: Double
    public var startedAt: Date
    public var estimatedSecondsRemaining: Double?

    public init(
        targetMM: Double,
        startMM: Double,
        currentMM: Double,
        startedAt: Date = Date(),
        estimatedSecondsRemaining: Double? = nil
    ) {
        self.targetMM = targetMM
        self.startMM = startMM
        self.currentMM = currentMM
        self.startedAt = startedAt
        self.estimatedSecondsRemaining = estimatedSecondsRemaining
    }

    /// 0...1 progress towards the target.
    public var fraction: Double {
        let total = abs(targetMM - startMM)
        guard total > 0.5 else { return 1 }
        return min(max(abs(currentMM - startMM) / total, 0), 1)
    }

    public func updating(currentMM: Double, estimatedSecondsRemaining: Double? = nil) -> MoveProgress {
        var copy = self
        copy.currentMM = currentMM
        copy.estimatedSecondsRemaining = estimatedSecondsRemaining
        return copy
    }
}
