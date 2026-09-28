import IdasenKit
import SwiftUI

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List(selection: $model.selection) {
            Section("Workspace") {
                ForEach([SidebarItem.desk, .presets, .activity]) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            Section("Preferences") {
                Label(SidebarItem.settings.title, systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Idasen")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConnectionFooter()
                .padding(16)
        }
        .background {
            if #unavailable(macOS 26) {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
            }
        }
    }

}

struct ConnectionFooter: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: DeskService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 9) {
                Image(systemName: "table.furniture")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).font(.callout.weight(.medium)).lineLimit(1)
                    Label(model.isDemoMode ? "Demo mode" : (desk.isConnected ? "Connected" : "Bluetooth"), systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
                Spacer(minLength: 0)
                if !desk.isConnected {
                    Button {
                        model.showPairing = true
                        model.startScanning()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Connect to a desk")
                }
            }
        }
    }

    private var statusColor: Color {
        if desk.isConnected { return .green }
        switch desk.connection {
        case .connecting, .reconnecting, .scanning: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    private var statusTitle: String {
        if desk.isConnected { return desk.connectedDeskName ?? "Connected" }
        switch desk.connection {
        case .scanning: return "Searching…"
        case .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .failed(let message): return message
        default: return "Not connected"
        }
    }
}

