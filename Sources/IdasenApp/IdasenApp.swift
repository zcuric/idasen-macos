import AppKit
import IdasenKit
import SwiftUI

@main
struct IdasenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.desk)
                .environmentObject(model.activity)
                .modifier(MotionPreferences(reduceMotion: model.settings.reduceMotion))
                .preferredColorScheme(Theme.colorScheme(model.settings.theme))
                .frame(minWidth: 940, minHeight: 640)
                .onAppear {
                    if CommandLine.arguments.contains("--dev-activity-fixture") {
                        DevTools.writeActivityFixture()
                        return
                    }
                    model.start()
                    if DevTools.isSnapshotRun { DevTools.runSnapshotSequence(model: model) }
                }
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unifiedCompact)
        .commands { DeskCommands(model: model) }

        MenuBarExtra(isInserted: model.binding(\.showMenuBarExtra)) {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.desk)
                .environmentObject(model.activity)
                .modifier(MotionPreferences(reduceMotion: model.settings.reduceMotion))
                .preferredColorScheme(Theme.colorScheme(model.settings.theme))
        } label: {
            MenuBarLabel(model: model, desk: model.desk)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsSceneView()
                .environmentObject(model)
                .environmentObject(model.desk)
                .environmentObject(model.activity)
                .modifier(MotionPreferences(reduceMotion: model.settings.reduceMotion))
                .preferredColorScheme(Theme.colorScheme(model.settings.theme))
                .frame(width: 640, height: 560)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.shutdown()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 216, max: 260)
        } detail: {
            ZStack {
                AmbientBackground(accent: Theme.accent(model.settings.accent))
                detail
            }
        }
        .background(DeskWindowReader { model.registerDeskWindow($0) })
        .overlay(alignment: .top) { BannerView() }
        .toolbar { DeskToolbar(model: model, desk: model.desk) }
        .sheet(isPresented: $model.showPairing) {
            PairingSheet()
        }
        .sheet(isPresented: $model.showEditor) {
            PresetEditorSheet(preset: model.editorPreset)
        }
        .sheet(isPresented: $model.showCalibration) {
            CalibrationSheet()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .desk:
            DeskView()
        case .presets:
            PresetsView()
        case .activity:
            ActivityView()
        case .settings:
            SettingsDetailView()
        }
    }
}

/// Only windows hosting the desk UI can handle press-and-hold movement keys.
private struct DeskWindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> DeskWindowTrackingView {
        let view = DeskWindowTrackingView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ view: DeskWindowTrackingView, context: Context) {
        view.onWindowChange = onWindowChange
    }
}

private final class DeskWindowTrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private struct DeskToolbar: ToolbarContent {
    let model: AppModel
    @ObservedObject var desk: DeskService

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if desk.connection.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .help(desk.connection.deskName.map { "Connecting to \($0)…" } ?? "Connecting…")
            }

            if desk.isConnected {
                if desk.isMoving {
                    Button {
                        desk.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Stop the desk (space or ⌘.)")
                    .accessibilityLabel("Stop the desk")
                }

                Button {
                    model.toggleSitStand()
                } label: {
                    Label(
                        model.sitStandState == .standing ? "Sit down" : "Stand up",
                        systemImage: model.sitStandState == .standing ? "chair.lounge.fill" : "figure.stand"
                    )
                }
                .disabled(desk.isMoving)
                .help(model.sitStandState == .standing ? "Move to the sit preset (⇧⌘T)" : "Move to the stand preset (⇧⌘T)")
            }

            Button {
                if desk.isConnected {
                    model.disconnect()
                } else {
                    model.showPairing = true
                    model.startScanning()
                }
            } label: {
                Label(
                    desk.isConnected ? "Disconnect" : "Connect",
                    systemImage: desk.isConnected ? "bolt.horizontal.circle" : "antenna.radiowaves.left.and.right"
                )
            }
            .help(desk.isConnected ? "Disconnect from the desk" : "Find your desk over Bluetooth")
            .accessibilityLabel(desk.isConnected ? "Disconnect from desk" : "Connect to desk")
        }
    }
}

// MARK: - Banner

struct BannerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let banner = model.banner {
            HStack(spacing: 9) {
                Image(systemName: banner.style.symbol)
                    .foregroundStyle(banner.style.color)
                Text(banner.text)
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(banner.style.color.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            .frame(maxWidth: 520)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.34, dampingFraction: 0.8), value: banner.id)
        }
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var desk: DeskService

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "table.furniture")
            if desk.isConnected, model.settings.menuBarShowsHeight, let height = desk.heightMM {
                Text(model.unit.format(millimeters: height))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(desk.isConnected ? "Idasen, \(model.heightText) \(model.unit.shortTitle)" : "Idasen, disconnected")

    }
}

// MARK: - Commands

/// Lightweight menu state. Updated only when a flag actually flips, so the
/// command menu is not rebuilt on every desk sample.
@MainActor
final class DeskMenuState: ObservableObject {
    @Published var isConnected = false
    @Published var isMoving = false
    @Published var isStanding = false
    @Published var canCapturePreset = false

    func update(from model: AppModel) {
        let connected = model.desk.isConnected
        let moving = model.desk.isMoving
        let standing = model.sitStandState == .standing
        let canCapture = model.desk.heightMM != nil

        if isConnected != connected { isConnected = connected }
        if isMoving != moving { isMoving = moving }
        if isStanding != standing { isStanding = standing }
        if canCapturePreset != canCapture { canCapturePreset = canCapture }
    }
}

struct DeskCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Desk") {
            DeskMenuItems(model: model, menu: model.menuState)
        }

        CommandGroup(after: .sidebar) {
            NavigationMenuItems(model: model)
        }
    }
}

struct DeskMenuItems: View {
    let model: AppModel
    @ObservedObject var menu: DeskMenuState

    var body: some View {
        Group {
            Button(menu.isStanding ? "Sit down" : "Stand up") {
                model.toggleSitStand()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!menu.isConnected || menu.isMoving)

            Button("Nudge up") { model.desk.nudge(byMM: model.settings.nudgeStepMM) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!menu.isConnected)
        }

        Divider()

        Group {
            Button("Nudge down") { model.desk.nudge(byMM: -model.settings.nudgeStepMM) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!menu.isConnected)

            Button("Stop") { model.desk.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!menu.isConnected)
        }

        Divider()

        Group {
            Button("Capture preset from current height") { model.addPresetFromCurrentHeight() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!menu.canCapturePreset)

            Button(menu.isConnected ? "Disconnect" : "Connect…") {
                if model.desk.isConnected {
                    model.disconnect()
                } else {
                    model.showPairing = true
                    model.startScanning()
                }
            }
        }
    }
}

struct NavigationMenuItems: View {
    let model: AppModel

    var body: some View {
        Group {
            Button("Desk") { model.selection = .desk }
                .keyboardShortcut("1", modifiers: .command)
            Button("Presets") { model.selection = .presets }
                .keyboardShortcut("2", modifiers: .command)
        }
        Button("Activity") { model.selection = .activity }
            .keyboardShortcut("3", modifiers: .command)
    }
}
