import AppKit
import IdasenKit
import SwiftUI

/// The menu bar popover.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService

    private var accent: Color { Theme.accent(model.settings.accent) }

    var body: some View {
        GlassControls {
        VStack(spacing: 12) {
            header
            TodaySummaryView(activity: model.activity, model: model, compact: true)
            movementControls
            if !model.presets.isEmpty {
                presets
            }
            footer
        }
        .padding(14)
        .frame(width: 336)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(desk.isConnected ? .green : .secondary)
                        .frame(width: 7, height: 7)
                    Text(desk.isConnected ? (desk.connectedDeskName ?? "Connected") : model.connectionTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                if desk.isConnected {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(model.heightText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text(model.unit.shortTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if desk.isMoving {
                StatusPill(
                    text: desk.movement == .up ? "Rising" : "Lowering",
                    symbol: desk.movement.symbolName,
                    color: accent,
                    pulsing: true
                )
            } else if desk.isConnected {
                Button {
                    model.toggleSitStand()
                } label: {
                    Label(
                        model.sitStandState == .standing ? "Sit" : "Stand",
                        systemImage: model.sitStandState == .standing ? "chair.lounge.fill" : "figure.stand"
                    )
                }
                .buttonStyle(ActionButtonStyle(tint: accent, compact: true))
            }
        }
    }

    // MARK: Controls

    private var movementControls: some View {
        HStack(spacing: 8) {
            HoldButton(symbol: "arrow.up", title: "Raise", tint: accent, enabled: desk.isConnected, height: 64,
                       onActivate: { desk.nudge(byMM: model.settings.nudgeStepMM) }) {
                desk.startHold(.up)
            } onRelease: {
                desk.endHold()
            }

            Button {
                desk.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 52, height: 64)
            }
            .buttonStyle(StopButtonStyle(prominent: desk.isMoving))
            .accessibilityLabel("Stop the desk")
            .disabled(!desk.isConnected)

            HoldButton(symbol: "arrow.down", title: "Lower", tint: accent, enabled: desk.isConnected, height: 64,
                       onActivate: { desk.nudge(byMM: -model.settings.nudgeStepMM) }) {
                desk.startHold(.down)
            } onRelease: {
                desk.endHold()
            }
        }
    }

    private var presets: some View {
        VStack(spacing: 6) {
            ForEach(model.presets.prefix(5)) { preset in
                Button {
                    model.move(to: preset)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: preset.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 16)
                        Text(preset.name)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(model.unit.format(millimeters: preset.heightMM))
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(GlassControlButtonStyle(radius: 8))
                .disabled(!desk.isConnected)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider().opacity(0.5)

            HStack(spacing: 8) {
                Button(desk.isConnected ? "Disconnect" : "Connect…") {
                    if desk.isConnected {
                        model.disconnect()
                    } else {
                        openMainWindow()
                        NSApp.activate(ignoringOtherApps: true)
                        model.showPairing = true
                        model.startScanning()
                    }
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))

                Spacer()

                Button("Open Idasen") {
                    openMainWindow()
                }
                .buttonStyle(ActionButtonStyle(tint: accent, compact: true))

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
                .help("Quit Idasen")
            }
        }
    }

    private func openMainWindow() {
        if !model.showDeskWindow() { openWindow(id: "main") }
        NSApp.activate(ignoringOtherApps: true)
    }
}
