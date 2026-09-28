import AppKit
import Carbon
import Foundation

// MARK: - Appearance

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum AccentChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case graphite
    case teal
    case green
    case amber
    case rose
    case violet

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var color: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .graphite: return .systemGray
        case .teal: return .systemTeal
        case .green: return .systemGreen
        case .amber: return .systemOrange
        case .rose: return .systemPink
        case .violet: return .systemPurple
        }
    }
}

// MARK: - Hot keys

/// A keyboard shortcut stored in a form that can be registered with Carbon's
/// `RegisterEventHotKey` (which works without Accessibility permissions).
public struct HotKeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, restricted to device-independent flags.
    public var modifiers: UInt

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    /// Human readable representation, e.g. `⌃⌥↑`.
    public var displayString: String {
        var text = ""
        let flags = modifierFlags
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += Self.keyName(for: keyCode)
        return text
    }

    public static func keyName(for keyCode: UInt16) -> String {
        let special: [UInt16: String] = [
            0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
            0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
            0x67: "F11", 0x6F: "F12",
        ]
        if let name = special[keyCode] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "?"
    }

    /// Translates a virtual key code into the current keyboard layout's character.
    static func character(for keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return -1
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

// MARK: - Settings

public struct AppSettings: Codable, Equatable, Sendable {
    public var unit: LengthUnit = .centimeters
    public var heightScale: HeightScale = .idasen

    // Connection
    public var autoConnect: Bool = true
    public var reconnectAutomatically: Bool = true
    public var launchAtLogin: Bool = false
    public var lastDeskID: UUID?
    public var lastName: String?
    public var didCompleteOnboarding: Bool = false

    // Desk behaviour
    public var warmUpBeforeMoves: Bool = true
    public var dpgCompatibility: Bool = false
    public var nudgeStepMM: Double = 10
    public var defaultMoveToleranceMM: Double = 4
    public var safetyMaxRunSeconds: Double = 45

    // Menu bar
    public var showMenuBarExtra: Bool = true
    public var menuBarShowsHeight: Bool = true

    // Notifications & reminders
    public var notifyOnArrival: Bool = true
    public var notifyOnConnectionChanges: Bool = false
    public var playSounds: Bool = false
    public var remindersEnabled: Bool = false
    public var reminderIntervalMinutes: Double = 45
    public var reminderOnlyWhileSitting: Bool = true

    // Activity
    public var dailyStandingGoalMinutes: Double = 120
    public var sitStandThresholdMM: Double = 0 // 0 = derive from sit/stand presets
    public var historyRetentionDays: Int = 120

    // Global hot keys
    public var globalHotKeysEnabled: Bool = false
    public var hotKeyUp: HotKeyCombo? = HotKeyCombo(keyCode: 0x7E, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)
    public var hotKeyDown: HotKeyCombo? = HotKeyCombo(keyCode: 0x7D, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)
    public var hotKeyStop: HotKeyCombo? = HotKeyCombo(keyCode: 0x01, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)
    public var hotKeyPresets: [UUID: HotKeyCombo] = [:]

    // Appearance
    public var theme: AppTheme = .system
    public var accent: AccentChoice = .blue
    public var reduceMotion: Bool = false

    public var demoMode: Bool = false

    public init() {}

    public static let defaultSitHeightMM = 730.0
    public static let defaultStandHeightMM = 1100.0

    public var sitPresetHeightMM: Double { AppSettings.defaultSitHeightMM }
    public var standPresetHeightMM: Double { AppSettings.defaultStandHeightMM }

    /// Height at which "sitting" becomes "standing" for activity tracking.
    public func sitStandThreshold(sitMM: Double?, standMM: Double?) -> Double {
        if sitStandThresholdMM > 0 { return sitStandThresholdMM }
        if let sit = sitMM, let stand = standMM, stand > sit {
            return (sit + stand) / 2
        }
        return 960
    }

    private enum CodingKeys: String, CodingKey {
        case unit, heightScale, autoConnect, reconnectAutomatically, launchAtLogin
        case lastDeskID, lastName, didCompleteOnboarding
        case warmUpBeforeMoves, dpgCompatibility, nudgeStepMM, defaultMoveToleranceMM, safetyMaxRunSeconds
        case showMenuBarExtra, menuBarShowsHeight
        case notifyOnArrival, notifyOnConnectionChanges, playSounds
        case remindersEnabled, reminderIntervalMinutes, reminderOnlyWhileSitting
        case dailyStandingGoalMinutes, sitStandThresholdMM, historyRetentionDays
        case globalHotKeysEnabled, hotKeyUp, hotKeyDown, hotKeyStop, hotKeyPresets
        case theme, accent, reduceMotion, demoMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        unit = try c.decodeIfPresent(LengthUnit.self, forKey: .unit) ?? defaults.unit
        heightScale = try c.decodeIfPresent(HeightScale.self, forKey: .heightScale) ?? defaults.heightScale
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? defaults.autoConnect
        reconnectAutomatically = try c.decodeIfPresent(Bool.self, forKey: .reconnectAutomatically) ?? defaults.reconnectAutomatically
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        lastDeskID = try c.decodeIfPresent(UUID.self, forKey: .lastDeskID)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        didCompleteOnboarding = try c.decodeIfPresent(Bool.self, forKey: .didCompleteOnboarding) ?? defaults.didCompleteOnboarding
        warmUpBeforeMoves = try c.decodeIfPresent(Bool.self, forKey: .warmUpBeforeMoves) ?? defaults.warmUpBeforeMoves
        dpgCompatibility = try c.decodeIfPresent(Bool.self, forKey: .dpgCompatibility) ?? defaults.dpgCompatibility
        nudgeStepMM = try c.decodeIfPresent(Double.self, forKey: .nudgeStepMM) ?? defaults.nudgeStepMM
        defaultMoveToleranceMM = try c.decodeIfPresent(Double.self, forKey: .defaultMoveToleranceMM) ?? defaults.defaultMoveToleranceMM
        safetyMaxRunSeconds = try c.decodeIfPresent(Double.self, forKey: .safetyMaxRunSeconds) ?? defaults.safetyMaxRunSeconds
        showMenuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? defaults.showMenuBarExtra
        menuBarShowsHeight = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowsHeight) ?? defaults.menuBarShowsHeight
        notifyOnArrival = try c.decodeIfPresent(Bool.self, forKey: .notifyOnArrival) ?? defaults.notifyOnArrival
        notifyOnConnectionChanges = try c.decodeIfPresent(Bool.self, forKey: .notifyOnConnectionChanges) ?? defaults.notifyOnConnectionChanges
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? defaults.playSounds
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? defaults.remindersEnabled
        reminderIntervalMinutes = try c.decodeIfPresent(Double.self, forKey: .reminderIntervalMinutes) ?? defaults.reminderIntervalMinutes
        reminderOnlyWhileSitting = try c.decodeIfPresent(Bool.self, forKey: .reminderOnlyWhileSitting) ?? defaults.reminderOnlyWhileSitting
        dailyStandingGoalMinutes = try c.decodeIfPresent(Double.self, forKey: .dailyStandingGoalMinutes) ?? defaults.dailyStandingGoalMinutes
        sitStandThresholdMM = try c.decodeIfPresent(Double.self, forKey: .sitStandThresholdMM) ?? defaults.sitStandThresholdMM
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? defaults.historyRetentionDays
        globalHotKeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalHotKeysEnabled) ?? defaults.globalHotKeysEnabled
        hotKeyUp = try c.decodeIfPresent(HotKeyCombo.self, forKey: .hotKeyUp) ?? defaults.hotKeyUp
        hotKeyDown = try c.decodeIfPresent(HotKeyCombo.self, forKey: .hotKeyDown) ?? defaults.hotKeyDown
        hotKeyStop = try c.decodeIfPresent(HotKeyCombo.self, forKey: .hotKeyStop) ?? defaults.hotKeyStop
        hotKeyPresets = try c.decodeIfPresent([UUID: HotKeyCombo].self, forKey: .hotKeyPresets) ?? defaults.hotKeyPresets
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? defaults.theme
        accent = try c.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? defaults.accent
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? defaults.reduceMotion
        demoMode = try c.decodeIfPresent(Bool.self, forKey: .demoMode) ?? defaults.demoMode
    }
}

// MARK: - Persistence

/// Minimal JSON file store rooted in `~/Library/Application Support/Idasen`.
public final class JSONStore<Value: Codable>: Sendable {
    public let url: URL

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Idasen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public init(filename: String, directory: URL? = nil) {
        url = (directory ?? Self.supportDirectory).appendingPathComponent(filename)
    }

    public func load(default defaultValue: Value) -> Value {
        guard let data = try? Data(contentsOf: url) else { return defaultValue }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Value.self, from: data)) ?? defaultValue
    }

    public func save(_ value: Value) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Observable wrapper around ``AppSettings``.
///
/// Writes are published only when the value actually changes. This matters:
/// callers such as `MenuBarExtra(isInserted:)` write the same value back during
/// their own KVO pass, and publishing on equal writes causes an endless
/// update loop that freezes the main thread.
public final class SettingsStore: ObservableObject {
    public var settings: AppSettings {
        get { storage }
        set {
            guard storage != newValue else { return }
            let oldValue = storage
            objectWillChange.send()
            storage = newValue
            scheduleSave()
            onChange?(oldValue, storage)
        }
    }

    /// Called after a change, with the previous and new values.
    public var onChange: ((AppSettings, AppSettings) -> Void)?

    private let store: JSONStore<AppSettings>
    private var storage: AppSettings
    private var pendingSave: DispatchWorkItem?

    public init(directory: URL? = nil) {
        store = JSONStore<AppSettings>(filename: "settings.json", directory: directory)
        storage = store.load(default: AppSettings())
    }

    public func reset() {
        settings = AppSettings()
    }

    /// Coalesce continuous control edits while preserving the latest value on quit.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushPendingSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    public func flushPendingSave() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        store.save(storage)
    }
}

/// Observable list of desk presets. Publishes only on real changes.
public final class PresetStore: ObservableObject {
    public var presets: [DeskPreset] {
        get { storage }
        set {
            guard storage != newValue else { return }
            objectWillChange.send()
            storage = newValue
            store.save(storage)
            onChange?(storage)
        }
    }

    /// Called after the list changed, with the new value.
    public var onChange: (([DeskPreset]) -> Void)?

    private let store: JSONStore<[DeskPreset]>
    private var storage: [DeskPreset]

    public init(directory: URL? = nil) {
        store = JSONStore<[DeskPreset]>(filename: "presets.json", directory: directory)
        let loaded = store.load(default: [])
        storage = loaded.isEmpty ? DeskPreset.default() : loaded
    }

    public var sitPreset: DeskPreset? { presets.first { $0.isSitPreset } }
    public var standPreset: DeskPreset? { presets.first { $0.isStandPreset } }

    public func add(_ preset: DeskPreset) {
        presets.append(preset)
    }

    public func update(_ preset: DeskPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
    }

    public func remove(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    public func move(from: IndexSet, to: Int) {
        let moving = from.sorted().map { presets[$0] }
        var result = presets
        for index in from.sorted(by: >) {
            result.remove(at: index)
        }
        let destination = to - from.filter { $0 < to }.count
        result.insert(contentsOf: moving, at: min(max(destination, 0), result.count))
        presets = result
    }

    public func markSit(_ id: UUID) {
        for index in presets.indices {
            presets[index].isSitPreset = presets[index].id == id
        }
    }

    public func markStand(_ id: UUID) {
        for index in presets.indices {
            presets[index].isStandPreset = presets[index].id == id
        }
    }

    public func sort(by height: Bool) {
        presets.sort { $0.heightMM < $1.heightMM }
    }
}
