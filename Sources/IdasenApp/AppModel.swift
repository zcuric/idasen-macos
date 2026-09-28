import AppKit
import Combine
import IdasenKit
import SwiftUI

/// A transient message shown at the top of the window.
struct Banner: Identifiable, Equatable {
    enum Style: Equatable {
        case info
        case success
        case warning
        case error

        var symbol: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    let id = UUID()
    var text: String
    var style: Style = .info
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case desk
    case presets
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desk: return "Desk"
        case .presets: return "Presets"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .desk: return "table.furniture"
        case .presets: return "bookmark.fill"
        case .activity: return "chart.bar.xaxis"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let settingsStore: SettingsStore
    let presetStore: PresetStore
    let desk = DeskService()
    let activity: ActivityRecorder
    let notifications = NotificationService()
    let menuState = DeskMenuState()

    @Published var selection: SidebarItem = .desk
    @Published var banner: Banner?
    @Published var editorPreset: DeskPreset?
    @Published var showEditor = false
    @Published var showPairing = false
    @Published var showCalibration = false
    @Published var showAllDevices = false
    @Published var isLaunchAtLoginEnabled = false

    private let hotKeys = GlobalHotKeys()
    private var keyMonitor: Any?
    private let deskWindows = NSHashTable<NSWindow>.weakObjects()
    private var reminderTimer: Timer?
    private var bannerTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var reminderSchedule = StandingReminderSchedule()
    private var didStart = false
    /// `--demo` forces demo mode for this launch only.
    private var demoOverride = false

    private init() {
        let directory = DevTools.isSnapshotRun ? DevTools.previewDirectory : nil
        settingsStore = SettingsStore(directory: directory)
        presetStore = PresetStore(directory: directory)
        activity = ActivityRecorder(directory: directory)
        if DevTools.isSnapshotRun {
            var preview = AppSettings()
            preview.demoMode = true
            preview.didCompleteOnboarding = true
            preview.notifyOnArrival = false
            preview.showMenuBarExtra = false
            preview.theme = DevTools.argumentValue("--dev-theme").flatMap(AppTheme.init(rawValue:)) ?? .light
            settingsStore.settings = preview
        }
    }

    // MARK: Derived

    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    var presets: [DeskPreset] { presetStore.presets }

    var unit: LengthUnit { settings.unit }

    var sitPreset: DeskPreset? { presetStore.sitPreset }
    var standPreset: DeskPreset? { presetStore.standPreset }

    var isDemoMode: Bool { settings.demoMode }

    var connectionTitle: String {
        switch desk.connection {
        case .idle: return "Not connected"
        case .scanning: return "Searching…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .connected(let name): return "Connected to \(name)"
        case .reconnecting(let attempt): return attempt > 1 ? "Reconnecting… (attempt \(attempt))" : "Reconnecting…"
        case .failed(let message): return message
        }
    }

    var heightText: String {
        guard let height = desk.heightMM else { return "–" }
        return unit.format(millimeters: height, showUnit: false)
    }

    var sitStandState: SitStandState {
        guard let height = desk.heightMM else { return .unknown }
        return height >= desk.sitStandThreshold ? .standing : .sitting
    }

    var menuBarTitle: String {
        guard let height = desk.heightMM, settings.menuBarShowsHeight else { return "" }
        return unit.format(millimeters: height, showUnit: false)
    }

    // MARK: Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        observeSystemEvents()

        if CommandLine.arguments.contains("--demo") {
            demoOverride = true
            settings.demoMode = true
        }

        desk.settings = settings
        desk.activity = activity
        activity.configure(retentionDays: settings.historyRetentionDays)
        syncPresetHeights()


        // Forward nested store changes so views only observe this object.
        settingsStore.onChange = { [weak self] old, new in
            guard let self else { return }
            self.applySettings(changedFrom: old, to: new)
            self.objectWillChange.send()
        }
        presetStore.onChange = { [weak self] _ in
            guard let self else { return }
            self.syncPresetHeights()
            self.objectWillChange.send()
        }

        desk.onArrived = { [weak self] target in self?.handleArrival(target) }
        desk.onMoveFailed = { [weak self] error in
            self?.banner(error.localizedDescription, style: .error)
        }
        desk.onError = { [weak self] error in
            self?.banner(error.localizedDescription, style: .error)
        }
        desk.onNotice = { [weak self] message in
            self?.banner(message, style: .warning)
        }
        desk.onConnectedNotification = { [weak self] name in
            self?.banner("Connected to \(name)", style: .success)
        }

        // Keep the (rarely rebuilt) command menu in sync with the desk.
        desk.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.menuState.update(from: self)
                    if !self.desk.isConnected { self.reminderSchedule.reset() }
                }
            }
            .store(in: &cancellables)

        if !DevTools.isSnapshotRun { notifications.configure(model: self) }
        installKeyMonitor()
        applySettings(changedFrom: nil, to: settings)
        if !DevTools.isSnapshotRun { startReminderTimer() }

        desk.connectIfConfigured()

        if !settings.didCompleteOnboarding {
            showPairing = true
        }
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.desk.stop()
                self?.activity.closeOpenSegment()
            }
        }
        workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.desk.stop()
            }
        }
    }

    func shutdown() {
        if demoOverride {
            // The flag is for a single launch; do not keep the desk simulated.
            settingsStore.settings.demoMode = false
        }
        desk.stop()
        activity.closeOpenSegment()
        activity.persist()
        settingsStore.flushPendingSave()
        hotKeys.unregisterAll()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    // MARK: - In-window keyboard control

    /// Handles the arrow keys and space in the main window so the desk can be
    /// driven from the keyboard: hold ↑/↓ to move, space to stop.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            var consumed = false
            MainActor.assumeIsolated {
                consumed = self.handleKeyEvent(event)
            }
            return consumed ? nil : event
        }
    }

    func registerDeskWindow(_ window: NSWindow?) {
        if let window { deskWindows.add(window) }
    }

    /// Returns true when the event was consumed by the desk controls.
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard selection == .desk else { return false }
        guard !showPairing, !showEditor, !showCalibration else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        guard !(event.window?.firstResponder is NSTextView) else { return false }
        guard let window = event.window, deskWindows.contains(window) else { return false }

        switch event.keyCode {
        case 126: // up arrow
            guard desk.isConnected else { return false }
            if event.type == .keyDown {
                if desk.holdingDirection != .up { desk.startHold(.up) }
            } else if desk.holdingDirection == .up {
                desk.endHold()
            }
            return true

        case 125: // down arrow
            guard desk.isConnected else { return false }
            if event.type == .keyDown {
                if desk.holdingDirection != .down { desk.startHold(.down) }
            } else if desk.holdingDirection == .down {
                desk.endHold()
            }
            return true

        case 49: // space
            guard desk.isConnected else { return false }
            if event.type == .keyDown, !event.isARepeat {
                desk.stop()
            }
            return true

        case 53: // escape
            guard desk.isConnected, desk.isMoving || desk.progress != nil else { return false }
            desk.stop()
            return true

        default:
            return false
        }
    }

    // MARK: Settings

    func binding<T: Equatable>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                // Never write equal values: SwiftUI controls (MenuBarExtra in
                // particular) write back the current value and that must not
                // trigger another update pass.
                guard self.settingsStore.settings[keyPath: keyPath] != newValue else { return }
                self.settingsStore.settings[keyPath: keyPath] = newValue
            }
        )
    }

    private func applySettings(changedFrom old: AppSettings?, to new: AppSettings) {
        // DeskService uses these values for movement and safety, so apply them immediately.
        desk.settings = new
        if old?.remindersEnabled != new.remindersEnabled
            || old?.reminderOnlyWhileSitting != new.reminderOnlyWhileSitting {
            reminderSchedule.reset()
        }
        if old == nil || old?.sitStandThresholdMM != new.sitStandThresholdMM {
            syncPresetHeights()
        }
        if old == nil {
            activity.configure(retentionDays: new.historyRetentionDays)
        }
        if !DevTools.isSnapshotRun, old == nil || old?.notifyOnArrival != new.notifyOnArrival
            || old?.notifyOnConnectionChanges != new.notifyOnConnectionChanges
            || old?.remindersEnabled != new.remindersEnabled {
            notifications.updateAuthorization()
        }
        if old == nil || old?.theme != new.theme { applyTheme() }
        if old == nil || old?.globalHotKeysEnabled != new.globalHotKeysEnabled
            || old?.hotKeyUp != new.hotKeyUp || old?.hotKeyDown != new.hotKeyDown
            || old?.hotKeyStop != new.hotKeyStop || old?.hotKeyPresets != new.hotKeyPresets {
            registerHotKeys()
        }
        if !DevTools.isSnapshotRun, old == nil || old?.launchAtLogin != new.launchAtLogin {
            updateLaunchAtLoginState()
        }
    }

    private func applyTheme() {
        switch settings.theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func syncPresetHeights() {
        desk.activitySitHeight = sitPreset?.heightMM ?? AppSettings.defaultSitHeightMM
        desk.activityStandHeight = standPreset?.heightMM ?? AppSettings.defaultStandHeightMM
    }

    func updateLaunchAtLoginState() {
        isLaunchAtLoginEnabled = LaunchAtLogin.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            settings.launchAtLogin = enabled
            updateLaunchAtLoginState()
        } catch {
            banner("Could not update login item: \(error.localizedDescription)", style: .error)
            settings.launchAtLogin = LaunchAtLogin.isEnabled
            updateLaunchAtLoginState()
        }
    }

    // MARK: Banners

    func banner(_ text: String, style: Banner.Style = .info) {
        let next = Banner(text: text, style: style)
        banner = next
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.banner?.id == next.id { self?.banner = nil }
            }
        }
    }

    // MARK: Desk actions

    func connect(to discovered: DiscoveredDesk) {
        desk.connect(to: discovered)
    }

    func connectSaved() {
        if !desk.connectSavedDesk() {
            showPairing = true
            desk.startScanning()
        }
    }

    func disconnect() {
        desk.disconnect()
    }

    func forgetDesk() {
        desk.forgetDesk()
        showPairing = true
        desk.startScanning()
    }

    func startScanning() {
        desk.startScanning()
    }

    func stopScanning() {
        desk.stopScanning()
    }

    func move(to preset: DeskPreset) {
        desk.go(toMM: preset.heightMM)
    }

    func move(toHeightMM mm: Double) {
        desk.go(toMM: mm)
    }

    func toggleSitStand() {
        guard let height = desk.heightMM else { return }
        let threshold = desk.sitStandThreshold
        if height >= threshold {
            if let sit = sitPreset {
                move(to: sit)
            } else {
                desk.go(toMM: AppSettings.defaultSitHeightMM)
            }
        } else {
            if let stand = standPreset {
                move(to: stand)
            } else {
                desk.go(toMM: AppSettings.defaultStandHeightMM)
            }
        }
    }

    func addPresetFromCurrentHeight() {
        guard let height = desk.heightMM else {
            banner("Connect to the desk first to capture its height", style: .warning)
            return
        }
        editorPreset = DeskPreset(name: "Preset \(presets.count + 1)", heightMM: (height / 10).rounded() * 10)
        showEditor = true
    }

    func editPreset(_ preset: DeskPreset) {
        editorPreset = preset
        showEditor = true
    }

    func saveEditedPreset(_ preset: DeskPreset) {
        if presets.contains(where: { $0.id == preset.id }) {
            presetStore.update(preset)
        } else {
            presetStore.add(preset)
        }
        banner("Saved \(preset.name)", style: .success)
    }

    func deletePreset(_ preset: DeskPreset) {
        presetStore.remove(id: preset.id)
        banner("Deleted \(preset.name)", style: .success)
    }

    func markSit(_ preset: DeskPreset) {
        presetStore.markSit(preset.id)
    }

    func markStand(_ preset: DeskPreset) {
        presetStore.markStand(preset.id)
    }

    // MARK: Hot keys

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        guard settings.globalHotKeysEnabled else { return }

        var failed: [String] = []

        if let combo = settings.hotKeyUp {
            let ok = hotKeys.register(combo, id: "up") { [weak self] in self?.desk.startHold(.up) } onRelease: { [weak self] in
                self?.desk.endHold()
            }
            if !ok { failed.append(combo.displayString) }
        }
        if let combo = settings.hotKeyDown {
            let ok = hotKeys.register(combo, id: "down") { [weak self] in self?.desk.startHold(.down) } onRelease: { [weak self] in
                self?.desk.endHold()
            }
            if !ok { failed.append(combo.displayString) }
        }
        if let combo = settings.hotKeyStop {
            let ok = hotKeys.register(combo, id: "stop") { [weak self] in self?.desk.stop() }
            if !ok { failed.append(combo.displayString) }
        }
        for preset in presets {
            if let combo = settings.hotKeyPresets[preset.id] {
                let ok = hotKeys.register(combo, id: "preset-\(preset.id.uuidString)") { [weak self] in
                    self?.move(to: preset)
                }
                if !ok { failed.append(combo.displayString) }
            }
        }

        if !failed.isEmpty {
            banner("Some shortcuts could not be registered (already in use?): \(failed.joined(separator: ", "))", style: .warning)
        }
    }

    // MARK: Reminders & notifications

    private func startReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStandingReminder() }
        }
    }

    private func checkStandingReminder() {
        let segment = activity.today.segments.last
        let sittingSince = sitStandState == .sitting && segment?.state == .sitting ? segment?.start : nil
        guard reminderSchedule.isDue(
            at: Date(), enabled: settings.remindersEnabled, connected: desk.isConnected,
            moving: desk.isMoving, sittingSince: sittingSince,
            onlyWhileSitting: settings.reminderOnlyWhileSitting,
            intervalMinutes: settings.reminderIntervalMinutes
        ) else { return }
        notifications.postStandingReminder()
    }

    func setStandingRemindersEnabled(_ enabled: Bool) {
        settings.remindersEnabled = enabled
        reminderSchedule.reset()
        checkStandingReminder()
        if enabled, !DevTools.isSnapshotRun { notifications.requestAuthorization() }
    }

    func snoozeReminder() {
        reminderSchedule.snooze(at: Date())
        banner("Reminder snoozed for 10 minutes", style: .info)
    }

    private func handleArrival(_ target: Double) {
        if settings.notifyOnArrival {
            notifications.postArrival(heightText: unit.format(millimeters: target))
        }
        if settings.playSounds {
            NSSound(named: "Glass")?.play()
        }
    }

    func standUpNow() {
        if let stand = standPreset {
            move(to: stand)
        } else {
            desk.go(toMM: AppSettings.defaultStandHeightMM)
        }
    }
}
