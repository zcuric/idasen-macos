import AppKit
import IdasenKit
import SwiftUI

struct SettingsDetailView: View {
    var body: some View {
        ScrollView {
            SettingsView()
                .padding(24)
        }
    }
}

struct SettingsSceneView: View {
    var body: some View {
        ScrollView {
            SettingsView(compact: true)
                .padding(16)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService

    var compact = false

    @State private var category: Category = .general

    private enum Category: String, CaseIterable, Identifiable {
        case general = "General", desk = "Desk", shortcuts = "Shortcuts", activity = "Activity", diagnostics = "Diagnostics"
        var id: Self { self }
    }

    @State private var pendingReset: ResetAction?

    private enum ResetAction {
        case today, activity, settings

        var title: String {
            switch self {
            case .today: "Clear today's activity?"
            case .activity: "Delete all activity history?"
            case .settings: "Reset all settings?"
            }
        }

        var buttonTitle: String {
            switch self {
            case .today: "Clear today"
            case .activity: "Delete activity"
            case .settings: "Reset settings"
            }
        }
    }

    private var accent: Color { Theme.accent(model.settings.accent) }
    private var scale: HeightScale { model.settings.heightScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !compact {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.system(size: 26, weight: .semibold))
                    Text("Units, desk limits, reminders, shortcuts and diagnostics.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Settings category", selection: $category) {
                ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 8)

            switch category {
            case .general:
                appearanceSection
                connectionSection
            case .desk:
                deskSection
            case .shortcuts:
                shortcutsSection
            case .activity:
                notificationsSection
                activitySection
            case .diagnostics:
                diagnosticsSection
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .confirmationDialog(
            pendingReset?.title ?? "",
            isPresented: Binding(
                get: { pendingReset != nil },
                set: { if !$0 { pendingReset = nil } }
            )
        ) {
            if let action = pendingReset {
                Button(action.buttonTitle, role: .destructive) {
                    performReset(action)
                    pendingReset = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingReset = nil }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        SettingsCard(title: "Appearance", symbol: "paintbrush.fill") {
            LabeledRow("Units") {
                Picker("", selection: model.binding(\.unit)) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }

            LabeledRow("Theme") {
                Picker("", selection: model.binding(\.theme)) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }

            LabeledRow("Accent") {
                HStack(spacing: 8) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            model.settings.accent = choice
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Theme.gradient(Theme.accent(choice)))
                                    .frame(width: 20, height: 20)
                                if model.settings.accent == choice {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 28, height: 28)
                        .help(choice.title)
                        .accessibilityLabel("\(choice.title) accent")
                        .accessibilityValue(model.settings.accent == choice ? "Selected" : "Not selected")
                    }
                }
            }

            Toggle("Reduce motion", isOn: model.binding(\.reduceMotion))
                .help("Minimize interface animations")
        }
    }

    // MARK: Desk

    private var deskSection: some View {
        SettingsCard(title: "Desk", symbol: "table.furniture") {
            LabeledRow("Lower limit") {
                limitControl(value: minimumBinding, range: 550...min(1200, scale.maximumMM - 100))
            }
            LabeledRow("Upper limit") {
                limitControl(value: maximumBinding, range: max(700, scale.minimumMM + 100)...1350)
            }

            LabeledRow("Height offset") {
                HStack(spacing: 10) {
                    Text(String(format: "%.1f cm", scale.offsetMM / 10))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                    Button("Calibrate…") { model.showCalibration = true }
                        .buttonStyle(ActionButtonStyle(tint: accent, filled: false, compact: true))
                }
            }

            LabeledRow("Nudge step") {
                Picker("", selection: model.binding(\.nudgeStepMM)) {
                    Text("1 mm").tag(1.0)
                    Text("5 mm").tag(5.0)
                    Text("1 cm").tag(10.0)
                    Text("2.5 cm").tag(25.0)
                    Text("5 cm").tag(50.0)
                }
                .labelsHidden()
                .frame(width: 120)
            }

            Toggle("Send wake-up before moves", isOn: model.binding(\.warmUpBeforeMoves))
                .help("Some controllers sleep between commands; a wake-up byte makes the first move reliable.")
            Toggle("LINAK DPG handset compatibility", isOn: model.binding(\.dpgCompatibility))
                .help("Enable when using a DPG1C hand controller instead of the IDÅSEN panel.")

            LabeledRow("Safety timeout") {
                HStack {
                    PrecisionSlider(value: model.binding(\.safetyMaxRunSeconds), in: 15...120, step: 5)
                        .tint(accent)
                        .frame(width: 180)
                    Text("\(Int(model.settings.safetyMaxRunSeconds)) s")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 46, alignment: .leading)
                }
            }

            Toggle("Demo mode", isOn: model.binding(\.demoMode))
                .help("Control a simulated desk — useful for exploring the app without hardware.")
            if model.isDemoMode {
                Text("Demo mode disconnects the real desk and simulates movement.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var minimumBinding: Binding<Double> {
        Binding(
            get: { model.settings.heightScale.minimumMM },
            set: { newValue in
                model.settings.heightScale.minimumMM = min(newValue, model.settings.heightScale.maximumMM - 50)
            }
        )
    }

    private var maximumBinding: Binding<Double> {
        Binding(
            get: { model.settings.heightScale.maximumMM },
            set: { newValue in
                model.settings.heightScale.maximumMM = max(newValue, model.settings.heightScale.minimumMM + 50)
            }
        )
    }

    private func limitControl(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            PrecisionSlider(value: value, in: range, step: 5)
                .tint(accent)
                .frame(width: 160)
            Text(model.unit.format(millimeters: value.wrappedValue))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 64, alignment: .leading)
        }
    }

    // MARK: Connection

    private var connectionSection: some View {
        SettingsCard(title: "Connection", symbol: "antenna.radiowaves.left.and.right") {
            Toggle("Connect automatically at launch", isOn: model.binding(\.autoConnect))
            Toggle("Reconnect when the connection drops", isOn: model.binding(\.reconnectAutomatically))

            LabeledRow("Launch at login") {
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { model.isLaunchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    if !model.isLaunchAtLoginEnabled {
                        Text(LaunchAtLogin.statusDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            LabeledRow("Menu bar") {
                HStack(spacing: 16) {
                    Toggle("Show icon", isOn: model.binding(\.showMenuBarExtra))
                        .disabled(model.settings.menuBarOnly)
                    Toggle("Show height", isOn: model.binding(\.menuBarShowsHeight))
                        .disabled(!model.settings.showMenuBarExtra)
                }
                .font(.system(size: 12))
            }

            Toggle("Run in menu bar only", isOn: Binding(
                get: { model.settings.menuBarOnly },
                set: { enabled in
                    if enabled { model.settings.showMenuBarExtra = true }
                    model.settings.menuBarOnly = enabled
                }
            ))
            Text("Takes effect on the next launch. Open the main window from the menu bar icon.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledRow("Saved desk") {
                HStack(spacing: 8) {
                    Text(model.settings.lastName ?? "None")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if model.settings.lastDeskID != nil {
                        Button("Forget") { model.forgetDesk() }
                            .buttonStyle(ActionButtonStyle(tint: .red, filled: false, compact: true))
                    }
                }
            }
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        SettingsCard(title: "Notifications & reminders", symbol: "bell.fill") {
            Toggle("Notify when the desk reaches a target", isOn: model.binding(\.notifyOnArrival))
            Toggle("Notify on connect and disconnect", isOn: model.binding(\.notifyOnConnectionChanges))
            Toggle("Play sound on arrival", isOn: model.binding(\.playSounds))

            Divider().opacity(0.5)

            StandingReminderPreferences(model: model, notifications: model.notifications)
        }
    }

    // MARK: Shortcuts

    private var shortcutsSection: some View {
        SettingsCard(title: "Global shortcuts", symbol: "command") {
            Toggle("Enable global shortcuts", isOn: model.binding(\.globalHotKeysEnabled))
            Text("Work outside the app — hold the shortcut to move, release to stop.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            if model.settings.globalHotKeysEnabled {
                HotKeyRecorderRow(title: "Raise desk", combo: model.binding(\.hotKeyUp))
                HotKeyRecorderRow(title: "Lower desk", combo: model.binding(\.hotKeyDown))
                HotKeyRecorderRow(title: "Stop", combo: model.binding(\.hotKeyStop))

                Divider().opacity(0.5)
                ForEach(model.presets) { preset in
                    HotKeyRecorderRow(
                        title: preset.name,
                        combo: Binding(
                            get: { model.settings.hotKeyPresets[preset.id] },
                            set: { newValue in
                                if let newValue {
                                    model.settings.hotKeyPresets[preset.id] = newValue
                                } else {
                                    model.settings.hotKeyPresets.removeValue(forKey: preset.id)
                                }
                            }
                        )
                    )
                }
            }
        }
    }

    // MARK: Activity

    private var activitySection: some View {
        SettingsCard(title: "Activity", symbol: "chart.bar.xaxis") {
            LabeledRow("Daily standing goal") {
                HStack {
                    PrecisionSlider(value: model.binding(\.dailyStandingGoalMinutes), in: 30...300, step: 15)
                        .tint(accent)
                        .frame(width: 180)
                    Text("\(Int(model.settings.dailyStandingGoalMinutes)) min")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .leading)
                }
            }

            LabeledRow("Sit/stand threshold") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        PrecisionSlider(
                            value: model.binding(\.sitStandThresholdMM),
                            in: 0...scale.maximumMM,
                            step: 10
                        )
                        .tint(accent)
                        .frame(width: 180)
                        Text(model.settings.sitStandThresholdMM == 0
                            ? "Auto (\(model.unit.format(millimeters: desk.sitStandThreshold)))"
                            : model.unit.format(millimeters: model.settings.sitStandThresholdMM))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 110, alignment: .leading)
                    }
                    if model.settings.sitStandThresholdMM != 0 {
                        Button("Use automatic threshold") {
                            model.settings.sitStandThresholdMM = 0
                        }
                        .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
                    }
                }
            }

            LabeledRow("Keep history") {
                Picker("", selection: model.binding(\.historyRetentionDays)) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("120 days").tag(120)
                    Text("180 days").tag(180)
                    Text("1 year").tag(365)
                }
                .labelsHidden()
                .frame(width: 120)
            }

            LabeledRow("") {
                HStack(spacing: 8) {
                    Button("Reset today") {
                        pendingReset = .today
                    }
                    .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
                    Button("Delete all activity") {
                        pendingReset = .activity
                    }
                    .buttonStyle(ActionButtonStyle(tint: .red, filled: false, compact: true))
                }
            }
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        SettingsCard(title: "Diagnostics", symbol: "stethoscope") {
            Text(desk.isConnected
                ? "Connected. Last update \(desk.lastSampleAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")."
                : "Not connected.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            if let sample = desk.lastRawSample {
                Text("Raw height units: \(sample.raw) · speed \(sample.speed)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(desk.log.prefix(60)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.date, format: .dateTime.hour().minute().second())
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(entry.message)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            .padding(8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button("Copy log") {
                    let text = desk.log
                        .map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.level.rawValue)] \($0.message)" }
                        .joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    model.banner("Log copied to the clipboard", style: .success)
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))

                Button("Reset all settings") {
                    pendingReset = .settings
                }
                .buttonStyle(ActionButtonStyle(tint: .red, filled: false, compact: true))
            }
        }
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func performReset(_ action: ResetAction) {
        switch action {
        case .today:
            model.activity.reset()
            model.banner("Today's activity cleared", style: .success)
        case .activity:
            model.activity.removeAllHistory()
            model.banner("Activity history deleted", style: .success)
        case .settings:
            model.settingsStore.reset()
            model.banner("Settings reset to defaults", style: .success)
        }
    }
}

// MARK: - Building blocks

struct SettingsCard<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, symbol: symbol)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 12.5))
        }
    }
}

struct LabeledRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            if !title.isEmpty {
                Text(title)
                    .frame(width: 170, alignment: .leading)
            }
            content
            Spacer(minLength: 0)
        }
    }
}

struct HotKeyRecorderRow: View {
    var title: String
    @Binding var combo: HotKeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledRow(title) {
            HStack(spacing: 8) {
                Text(combo?.displayString ?? "—")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(minWidth: 52, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Button(isRecording ? "Press keys…" : "Record") {
                    isRecording ? stopRecording() : startRecording()
                }
                .buttonStyle(ActionButtonStyle(
                    tint: isRecording ? .orange : .secondary,
                    filled: isRecording,
                    compact: true
                ))

                if combo != nil {
                    Button("Clear") { combo = nil }
                        .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // escape cancels
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.isEmpty else { return nil }
            combo = HotKeyCombo(keyCode: event.keyCode, modifiers: flags.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
