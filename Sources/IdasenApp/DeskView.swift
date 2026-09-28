import IdasenKit
import SwiftUI

struct DeskView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService

    @State private var targetMM: Double = AppSettings.defaultStandHeightMM
    @State private var isEditingTarget = false
    @Namespace private var actionGlass
    @Environment(\.appReduceMotion) private var reduceMotion

    private var accent: Color { Theme.accent(model.settings.accent) }
    private var scale: HeightScale { model.settings.heightScale }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    TodaySummaryView(activity: model.activity, model: model)

                    if geometry.size.width < 650 {
                        VStack(spacing: 16) {
                            heightCard
                            illustrationCard
                            targetCard
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            illustrationCard
                            .frame(maxWidth: .infinity)

                            heightCard
                                .frame(width: 290)
                        }
                    }

                    presetsCard
                    if geometry.size.width >= 650 { targetCard }
                    hints
                }
                .padding(24)
                .frame(maxWidth: 1220)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onChange(of: desk.heightMM) { _, newValue in
            guard let newValue, !isEditingTarget, desk.progress == nil else { return }
            targetMM = newValue
        }
        .onAppear {
            if let height = desk.heightMM {
                targetMM = height
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your workspace")
                    .font(.system(size: 26, weight: .semibold))
                Text(model.connectionTitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isDemoMode {
                StatusPill(text: "Demo", symbol: "sparkles", color: .purple)
            }

            if desk.bluetooth != .ready, !model.isDemoMode {
                StatusPill(
                    text: desk.bluetooth.title,
                    symbol: desk.bluetooth.symbolName,
                    color: .orange
                )
            }

            if desk.isConnected {
                StatusPill(text: "Connected", symbol: "wave.3.right", color: .green)
            }
        }
    }

    // MARK: Illustration

    private var illustrationCard: some View {
        ContentCard(padding: 20) {
            ZStack {
                DeskIllustration(
                    heightMM: desk.heightMM,
                    targetMM: desk.progress?.targetMM,
                    scale: scale,
                    accent: accent,
                    isMoving: desk.isMoving,
                    unit: model.unit
                )
                .equatable()
                .frame(height: 254)
                .opacity(desk.isConnected ? 1 : 0.42)
                .animation(model.settings.reduceMotion ? nil : .linear(duration: 0.14), value: desk.heightMM)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: desk.isConnected)

                if !desk.isConnected {
                    disconnectedOverlay
                }
            }
        }
    }

    private var disconnectedOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(desk.connection.isBusy ? "Searching for your desk…" : "Desk not connected")
                .font(.system(size: 13.5, weight: .semibold))
            Text("Wake the desk with its handset, then connect over Bluetooth.")
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Find desk") {
                    model.showPairing = true
                    model.startScanning()
                }
                .buttonStyle(ActionButtonStyle(tint: accent, compact: true))

                if model.settings.lastDeskID != nil {
                    Button("Reconnect") { model.connectSaved() }
                        .buttonStyle(ActionButtonStyle(tint: accent, filled: false, compact: true))
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Target

    private var targetCard: some View {
        ContentCard {
            VStack(spacing: 10) {
                HStack {
                    SectionHeader(title: "Choose a height")
                    Spacer()
                    Text(model.unit.format(millimeters: targetMM))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }

                Slider(
                    value: Binding(get: { targetMM }, set: { targetMM = ($0 / 5).rounded() * 5 }),
                    in: scale.minimumMM...scale.maximumMM,
                    onEditingChanged: { editing in
                        isEditingTarget = editing
                    }
                )
                .tint(accent)
                .disabled(!desk.isConnected)
                .accessibilityLabel("Target height")
                .accessibilityValue(model.unit.format(millimeters: targetMM))

                HStack(spacing: 4) {
                    Text(model.unit.format(millimeters: scale.minimumMM, showUnit: false))
                    Spacer()
                    if #available(macOS 26, *) {
                        GlassEffectContainer(spacing: 6) { nudgeRow }
                    } else {
                        nudgeRow
                    }
                    Spacer()
                    Text(model.unit.format(millimeters: scale.maximumMM, showUnit: false))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

                if #available(macOS 26, *) {
                    GlassEffectContainer(spacing: 8) { moveActionRow }
                } else {
                    moveActionRow
                }
            }
        }
    }

    private var moveActionRow: some View {
        HStack(spacing: 8) {
            Button {
                model.move(toHeightMM: targetMM)
            } label: {
                Label("Move desk", systemImage: "arrow.up.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(tint: accent))
            .modifier(GlassControlIdentity(id: "move", namespace: actionGlass))
            .disabled(!desk.isConnected || desk.isMoving)
            .opacity(desk.isConnected ? 1 : 0.5)

            if desk.progress != nil {
                Button("Cancel") { desk.stop() }
                    .buttonStyle(ActionButtonStyle(tint: .red, filled: false))
                    .modifier(GlassControlIdentity(id: "cancel", namespace: actionGlass))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: desk.progress != nil)
    }

    private func nudgeButton(_ title: String, delta: Double) -> some View {
        Button(title) {
            desk.nudge(byMM: delta)
        }
        .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
        .disabled(!desk.isConnected)
    }

    private var nudgeRow: some View {
        HStack(spacing: 6) {
            nudgeButton("−1 cm", delta: -10)
            nudgeButton("−5 mm", delta: -5)
            nudgeButton("+5 mm", delta: 5)
            nudgeButton("+1 cm", delta: 10)
        }
    }

    // MARK: Side column

    private var heightCard: some View {
        GlassControls {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.heightText)
                        .font(.system(size: 58, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(model.unit.shortTitle)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                movementRow

                Divider().opacity(0.5)

                HStack(spacing: 8) {
                    HoldButton(
                        symbol: "arrow.up",
                        title: "Raise",
                        tint: accent,
                        enabled: desk.isConnected,
                        onActivate: { desk.nudge(byMM: model.settings.nudgeStepMM) }
                    ) {
                        desk.startHold(.up)
                    } onRelease: {
                        desk.endHold()
                    }

                    stopButton

                    HoldButton(
                        symbol: "arrow.down",
                        title: "Lower",
                        tint: accent,
                        enabled: desk.isConnected,
                        onActivate: { desk.nudge(byMM: -model.settings.nudgeStepMM) }
                    ) {
                        desk.startHold(.down)
                    } onRelease: {
                        desk.endHold()
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        model.toggleSitStand()
                    } label: {
                        Label(
                            model.sitStandState == .standing ? "Sit down" : "Stand up",
                            systemImage: model.sitStandState == .standing ? "chair.lounge.fill" : "figure.stand"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(tint: accent, filled: false))
                    .disabled(!desk.isConnected || desk.isMoving)
                }
            }
            .padding(Theme.cardPadding)
        }
    }

    private var stopButton: some View {
        Button {
            desk.stop()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("Stop")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
        }
        .buttonStyle(StopButtonStyle(prominent: desk.isMoving))
        .disabled(!desk.isConnected)
        .help("Stop movement (space)")
        .accessibilityLabel("Stop the desk")
    }

    private var movementRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: desk.movement.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(desk.isMoving ? accent : .secondary)
                Text(desk.movement.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((desk.isMoving ? accent.opacity(0.14) : Color.primary.opacity(0.06)), in: Capsule())

            if desk.isMoving, desk.speedMMps > 1 {
                Text(String(format: "%.1f cm/s", desk.speedMMps / 10))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if let progress = desk.progress {
                Text("→ \(model.unit.format(millimeters: progress.targetMM))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var presetsCard: some View {
        VStack(spacing: 12) {
                HStack {
                    SectionHeader(title: "Your positions")
                    Button { model.addPresetFromCurrentHeight() } label: {
                        Label("Save current", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!desk.isConnected)
                }

                if model.presets.isEmpty {
                    EmptyStateView(
                        symbol: "bookmark",
                        title: "No presets yet",
                        message: "Capture your favourite heights to move there with one click."
                    )
                } else {
                    GlassControls(spacing: 8) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(4, max(1, model.presets.count))), spacing: 12) {
                        ForEach(model.presets) { preset in
                            PresetChip(preset: preset, unit: model.unit, accent: accent, isCurrent: isCurrent(preset)) {
                                model.move(to: preset)
                            }
                            .disabled(!desk.isConnected)
                            .contextMenu {
                                Button("Move here") { model.move(to: preset) }
                                Button("Edit…") { model.editPreset(preset) }
                                Divider()
                                Button("Set as sit preset") { model.markSit(preset) }
                                Button("Set as stand preset") { model.markStand(preset) }
                                Divider()
                                Button("Delete", role: .destructive) { model.deletePreset(preset) }
                            }
                        }
                    }
                    }
                }

        }
    }

    private func isCurrent(_ preset: DeskPreset) -> Bool {
        guard let height = desk.heightMM else { return false }
        return abs(height - preset.heightMM) < 6
    }

    private var hints: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                keyboardHints
                Spacer()
                safetyHint
            }
            VStack(alignment: .leading, spacing: 8) {
                keyboardHints
                safetyHint
            }
        }
        .padding(.horizontal, 4)
    }

    private var keyboardHints: some View {
        HStack(spacing: 14) {
            KeyHint(keys: "↑ ↓", label: "hold to move")
            KeyHint(keys: "space", label: "stop")
            KeyHint(keys: "⌘1–⌘3", label: "sections")
        }
    }

    private var safetyHint: some View {
        Text("Release to stop · Hold to move")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

struct StopButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .modifier(GlassControlSurface(tint: prominent ? .red.opacity(0.4) : nil))
    }
}

struct PresetChip: View {
    var preset: DeskPreset
    var unit: LengthUnit
    var accent: Color
    var isCurrent: Bool
    var action: () -> Void


    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                    Spacer()
                    if preset.isSitPreset || preset.isStandPreset {
                        Text(preset.isSitPreset ? "SIT" : "STAND")
                            .font(.system(size: 8, weight: .heavy))
                            .kerning(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                (isCurrent ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)),
                                in: Capsule()
                            )
                    }
                }
                Text(preset.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(unit.format(millimeters: preset.heightMM))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(GlassControlButtonStyle(tint: isCurrent ? accent.opacity(0.25) : nil, radius: 13))
        .help("\(preset.name) — \(unit.format(millimeters: preset.heightMM))")
    }
}
