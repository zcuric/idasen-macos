import AppKit
import IdasenKit
import SwiftUI

struct PairingSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion

    @State private var attemptedScan = false

    private var accent: Color { Theme.accent(model.settings.accent) }
    private var scanning: Bool { desk.connection == .scanning }
    private var connecting: Bool { desk.connection.isBusy && !scanning || desk.connection.isConnected }
    private var bluetoothBlocked: Bool {
        guard !model.isDemoMode else { return false }
        return [.poweredOff, .unauthorized, .unsupported].contains(desk.bluetooth)
    }

    private var visibleDesks: [DiscoveredDesk] {
        model.showAllDevices ? desk.discovered : desk.discovered.filter(\.isIdasen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.isDemoMode { instructions }
                    discovery
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer.padding(20)
        }
        .frame(width: 540, height: 590)
        .tint(accent)
        .onChange(of: desk.isConnected, initial: true) { _, connected in
            if connected {
                model.settings.didCompleteOnboarding = true
                dismiss()
            }
        }
        .onDisappear {
            if scanning { model.stopScanning() }
        }
        .task(id: scanning) {
            guard scanning else { return }
            do {
                try await Task.sleep(for: .seconds(15))
                if scanning { model.stopScanning() }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: model.isDemoMode ? "table.furniture" : "antenna.radiowaves.left.and.right")
                .font(.title2.weight(.medium))
                .foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isDemoMode ? "Connect to a demo desk" : "Connect your IDÅSEN")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.isDemoMode ? "Explore height controls with a simulated desk." : "Connect directly from Idasen over Bluetooth.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("Turn on Bluetooth", detail: "Keep your Mac near the desk. Allow Bluetooth access when macOS asks.", symbol: "laptopcomputer")
            step("Wake the desk", detail: "Tap its physical height control. Disconnect any phone app already connected to the desk.", symbol: "hand.tap")
            step("Choose your desk", detail: "Click Find desk, then select the entry named Desk or DESK-xxxxx.", symbol: "table.furniture")
            Link("IKEA setup and troubleshooting", destination: URL(string: "https://zcuric.github.io/idasen-macos/#connect")!)
        }
    }

    private func step(_ title: String, detail: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .frame(width: 21)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 10) {
            if connecting {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(desk.connection.deskName.map { "Connecting to \($0)…" } ?? "Reconnecting…")
                }
            } else if bluetoothBlocked {
                bluetoothHelp
            } else {
                if scanning || attemptedScan || !visibleDesks.isEmpty {
                    Label(discoveryTitle, systemImage: "dot.radiowaves.left.and.right")
                        .symbolEffect(.pulse, options: .repeating, isActive: scanning && !reduceMotion)
                        .font(.subheadline.weight(.semibold))
                }

                if !visibleDesks.isEmpty {
                    ForEach(visibleDesks) { discovered in
                        Button {
                            model.connect(to: discovered)
                        } label: {
                            HStack {
                                Label(discovered.name, systemImage: discovered.isIdasen ? "table.furniture" : "antenna.radiowaves.left.and.right")
                                Spacer()
                                SignalBars(bars: discovered.signalBars, color: .secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Connect to this device")
                    }
                }

                if case .failed(let message) = desk.connection {
                    Text(message).foregroundStyle(.secondary)
                }

                if attemptedScan, !model.isDemoMode {
                    Toggle("Show all Bluetooth devices", isOn: $model.showAllDevices)
                        .toggleStyle(.checkbox)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: scanning)
    }

    private var discoveryTitle: String {
        if scanning { return "Looking for nearby desks…" }
        return visibleDesks.isEmpty ? "No desks found. Wake the handset and scan again." : "Nearby devices"
    }

    private var bluetoothHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(desk.bluetooth.title, systemImage: desk.bluetooth.symbolName)
                .font(.subheadline.weight(.semibold))

            switch desk.bluetooth {
            case .poweredOff:
                Text("Turn on Bluetooth in Control Center, then click Find desk.")
            case .unauthorized:
                Text("In System Settings › Privacy & Security › Bluetooth, allow Idasen. Reopen the app if macOS asks you to.")
            case .unsupported:
                Text("This Mac can still run the simulated desk in Demo mode.")
            default:
                EmptyView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !model.isDemoMode && !connecting {
                Button("Try demo") {
                    if scanning { model.stopScanning() }
                    model.settings.demoMode = true
                    model.connectSaved()
                }
            }
            Spacer()
            Button(connecting ? "Close" : "Not now") {
                model.settings.didCompleteOnboarding = true
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            if scanning {
                Button("Stop scan") { model.stopScanning() }
            } else {
                Button(attemptedScan ? "Scan again" : "Find desk") {
                    attemptedScan = true
                    model.startScanning()
                }
                .buttonStyle(.borderedProminent)
                .disabled(connecting || (!model.isDemoMode && desk.bluetooth == .unsupported))
            }
        }
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
