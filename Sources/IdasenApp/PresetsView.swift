import IdasenKit
import SwiftUI

struct PresetsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService

    private var accent: Color { Theme.accent(model.settings.accent) }

    var body: some View {
        VStack(spacing: 16) {
            header

            ContentCard(padding: 6) {
                if model.presets.isEmpty {
                    EmptyStateView(
                        symbol: "bookmark",
                        title: "No presets",
                        message: "Save the heights you use most and reach them with one click.",
                        action: ("Capture current height", { model.addPresetFromCurrentHeight() })
                    )
                } else {
                    presetList
                }
            }

        }
        .padding(24)
        .frame(maxWidth: 780, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Presets")
                    .font(.system(size: 26, weight: .semibold))
                Text("Drag to reorder. Right-click a preset for more options.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.addPresetFromCurrentHeight()
            } label: {
                Label("Capture current height", systemImage: "plus")
            }
            .buttonStyle(ActionButtonStyle(tint: accent, compact: true))
            .disabled(!desk.isConnected)
        }
    }

    private var presetList: some View {
        List {
            ForEach(model.presets) { preset in
                PresetRow(
                    preset: preset,
                    unit: model.unit,
                    accent: accent,
                    isCurrent: isCurrent(preset),
                    isConnected: desk.isConnected
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
            .onMove { indices, destination in
                model.presetStore.move(from: indices, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 180, maxHeight: .infinity)
    }

    private func isCurrent(_ preset: DeskPreset) -> Bool {
        guard let height = desk.heightMM else { return false }
        return abs(height - preset.heightMM) < 6
    }
}

struct PresetRow: View {
    var preset: DeskPreset
    var unit: LengthUnit
    var accent: Color
    var isCurrent: Bool
    var isConnected: Bool

    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: preset.symbolName, tint: isCurrent ? accent : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                    if preset.isSitPreset {
                        badge("SIT", color: .blue)
                    }
                    if preset.isStandPreset {
                        badge("STAND", color: .green)
                    }
                }
                Text(unit.format(millimeters: preset.heightMM))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isCurrent {
                StatusPill(text: "Here", symbol: "location.fill", color: accent)
            }

            HStack(spacing: 6) {
                Button("Move") { model.move(to: preset) }
                    .buttonStyle(ActionButtonStyle(tint: accent, filled: false, compact: true))
                    .disabled(!isConnected)

                Button {
                    model.editPreset(preset)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary, filled: false, compact: true))
            }
            .opacity(hovering || isCurrent ? 1 : 0.72)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { model.editPreset(preset) }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy))
            .kerning(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}
