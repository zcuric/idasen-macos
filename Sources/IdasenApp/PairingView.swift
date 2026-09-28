import AppKit
import IdasenKit
import SwiftUI

// MARK: - Pairing sheet

struct PairingSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService
    @Environment(\.dismiss) private var dismiss

    private var accent: Color { Theme.accent(model.settings.accent) }

    private var visibleDesks: [DiscoveredDesk] {
        model.showAllDevices ? desk.discovered : desk.discovered.filter(\.isIdasen)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 480, height: 560)
        .background(.regularMaterial)
        .onAppear {
            if !desk.connection.isBusy, !desk.isConnected {
                model.startScanning()
            }
        }
        .onChange(of: desk.isConnected) { _, connected in
            if connected { dismiss() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.gradient(accent))
                    .frame(width: 38, height: 38)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect your desk")
                    .font(.system(size: 15, weight: .semibold))
                Text("Press a button on the desk to wake it up first.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if desk.isConnected {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                Text("Connected to \(desk.connectedDeskName ?? "desk")")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleDesks.isEmpty {
            scanningState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleDesks) { discovered in
                        DeviceRow(discovered: discovered, accent: accent) {
                            model.connect(to: discovered)
                        } isBusy: {
                            if case .connecting(let name) = desk.connection, name == discovered.name { return true }
                            return false
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private var scanningState: some View {
        VStack(spacing: 18) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(accent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 60, height: 60)
                        .scaleEffect(1 + CGFloat(index) * 0.62)
                        .opacity(0.9 - Double(index) * 0.28)
                }
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 60, height: 60)
                Image(systemName: "table.furniture")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .frame(height: 160)

            VStack(spacing: 6) {
                Text("Searching for nearby desks…")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("IDÅSEN desks advertise themselves as “Desk”.\nTap a desk button to wake the controller.")
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let id = model.settings.lastDeskID {
                Button {
                    model.connectSaved()
                } label: {
                    Label("Reconnect to \(model.settings.lastName ?? "saved desk")", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ActionButtonStyle(tint: accent, filled: false, compact: true))
                .help("Reconnect using the saved Bluetooth identifier \(id.uuidString.prefix(8))…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Show all Bluetooth devices", isOn: $model.showAllDevices)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

            Spacer()

            Button {
                model.startScanning()
            } label: {
                Label("Scan again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ActionButtonStyle(tint: accent, filled: false, compact: true))
            .disabled(desk.connection.isBusy)
        }
        .padding(14)
    }
}

struct DeviceRow: View {
    var discovered: DiscoveredDesk
    var accent: Color
    var connect: () -> Void
    var isBusy: () -> Bool

    var body: some View {
        Button(action: connect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            discovered.isIdasen
                                ? AnyShapeStyle(Theme.gradient(accent))
                                : AnyShapeStyle(Color.primary.opacity(0.08))
                        )
                    Image(systemName: discovered.isIdasen ? "table.furniture" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(discovered.isIdasen ? .white : .secondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(discovered.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(discovered.isIdasen ? "IKEA IDÅSEN controller" : "Bluetooth device")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SignalBars(bars: discovered.signalBars, color: .secondary)
                if isBusy() {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverLift(scale: 1.008, offset: 0)
    }
}

// MARK: - Preset editor

struct PresetEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService
    @Environment(\.dismiss) private var dismiss

    let preset: DeskPreset?

    @State private var name = ""
    @State private var heightMM: Double = 900
    @State private var symbol = "bookmark.fill"
    @State private var isSit = false
    @State private var isStand = false

    private var accent: Color { Theme.accent(model.settings.accent) }
    private var scale: HeightScale { model.settings.heightScale }

    private let symbols = DeskPreset(name: "", heightMM: 0).symbolCandidates

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(preset == nil ? "New preset" : "Edit preset")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 16) {
                labeled("Name") {
                    TextField("Preset name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                labeled("Height — \(model.unit.format(millimeters: heightMM))") {
                    HStack(spacing: 10) {
                        PrecisionSlider(value: $heightMM, in: scale.minimumMM...scale.maximumMM, step: 5)
                            .tint(accent)
                        Stepper(
                            value: $heightMM,
                            in: scale.minimumMM...scale.maximumMM,
                            step: 5
                        ) {
                            Text(model.unit.format(millimeters: heightMM))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 62, alignment: .trailing)
                        }
                    }
                    if desk.isConnected, let current = desk.heightMM {
                        Button("Use current height (\(model.unit.format(millimeters: current)))") {
                            heightMM = (current / 5).rounded() * 5
                        }
                        .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
                    }
                }

                labeled("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.adaptive(minimum: 32), spacing: 6), count: 8), spacing: 6) {
                        ForEach(symbols, id: \.self) { candidate in
                            Button {
                                symbol = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(symbol == candidate ? .white : .primary)
                                    .background(
                                        symbol == candidate
                                            ? AnyShapeStyle(Theme.gradient(accent))
                                            : AnyShapeStyle(Color.primary.opacity(0.07)),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                labeled("Roles") {
                    HStack(spacing: 14) {
                        Toggle("Sit preset", isOn: $isSit)
                        Toggle("Stand preset", isOn: $isStand)
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                }
            }
            .padding(16)

            Divider().opacity(0.5)

            HStack {
                if let preset, model.presets.contains(where: { $0.id == preset.id }) {
                    Button("Delete", role: .destructive) {
                        model.deletePreset(preset)
                        dismiss()
                    }
                    .buttonStyle(ActionButtonStyle(tint: .red, filled: false))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
                Button(preset == nil ? "Add preset" : "Save") {
                    save()
                }
                .buttonStyle(ActionButtonStyle(tint: accent))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .onAppear(perform: load)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func load() {
        let preset = preset ?? DeskPreset(name: "", heightMM: desk.heightMM ?? 900)
        name = preset.name
        heightMM = preset.heightMM
        symbol = preset.symbolName
        isSit = preset.isSitPreset
        isStand = preset.isStandPreset
    }

    private func save() {
        var edited = preset ?? DeskPreset(name: name, heightMM: heightMM)
        edited.name = name.trimmingCharacters(in: .whitespaces)
        edited.heightMM = heightMM
        edited.symbolName = symbol
        edited.isSitPreset = isSit
        edited.isStandPreset = isStand

        if isSit {
            model.presetStore.presets.removeAll { $0.isSitPreset && $0.id != edited.id }
        }
        model.saveEditedPreset(edited)
        dismiss()
    }
}

// MARK: - Calibration

struct CalibrationSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService
    @Environment(\.dismiss) private var dismiss

    @State private var measuredMM: Double = 730

    private var accent: Color { Theme.accent(model.settings.accent) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Height calibration")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 14) {
                Text("The controller reports heights relative to an assumed floor offset of \(Int(model.settings.heightScale.offsetMM)) cm. If your desk was re-calibrated, its reported heights may be shifted. Measure the desk surface with a tape measure, enter the real value below, and Idasen will adjust the offset.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ContentCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        row("Reported by desk", desk.heightMM.map { model.unit.format(millimeters: $0) } ?? "—")
                        row("Raw units", desk.lastRawSample.map { String($0.raw) } ?? "—")
                        row("Current offset", String(format: "%.1f cm", model.settings.heightScale.offsetMM / 10))
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Actual measured height")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        PrecisionSlider(value: $measuredMM, in: 550...1350, step: 1)
                            .tint(accent)
                        Text(model.unit.format(millimeters: measuredMM))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                    Button("Use current reported height") {
                        if let height = desk.heightMM { measuredMM = height }
                    }
                    .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
                    .disabled(desk.heightMM == nil)
                }
            }
            .padding(16)

            Divider().opacity(0.5)

            HStack {
                Button("Reset to 62 cm") {
                    model.settings.heightScale.offsetMM = 620
                    model.banner("Height offset reset", style: .success)
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false))
                .disabled(desk.heightMM == nil)

                Spacer()

                Button("Apply") {
                    apply()
                }
                .buttonStyle(ActionButtonStyle(tint: accent))
                .disabled(desk.heightMM == nil || desk.lastRawSample == nil)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 470)
        .background(.regularMaterial)
        .onAppear {
            if let height = desk.heightMM { measuredMM = height }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private func apply() {
        guard let sample = desk.lastRawSample else { return }
        let newOffset = measuredMM - Double(sample.raw) / 10
        guard newOffset > 200, newOffset < 1200 else {
            model.banner("That measurement does not look right for an IDÅSEN", style: .warning)
            return
        }
        model.settings.heightScale.offsetMM = newOffset
        model.banner(String(format: "Offset set to %.1f cm", newOffset / 10), style: .success)
        dismiss()
    }
}
