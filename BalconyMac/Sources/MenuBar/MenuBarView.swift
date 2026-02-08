import SwiftUI
import BalconyShared

struct MenuBarView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var sessionListModel: SessionListModel
    @State private var showingQRCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerSection

            Divider()

            // Connected Devices
            devicesSection

            Divider()

            // Active Sessions
            sessionsSection

            Divider()

            // Actions
            Button("Pair New Device...") {
                showingQRCode = true
            }

            Button("Preferences...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit Balcony") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
        .sheet(isPresented: $showingQRCode) {
            QRCodePairingView(connectionManager: connectionManager)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Image(systemName: connectionManager.statusIconName)
                .foregroundStyle(connectionManager.isServerRunning ? .green : .red)
            Text("Balcony")
                .font(.headline)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var devicesSection: some View {
        Section("Devices") {
            if connectionManager.connectedDevices.isEmpty {
                Text("No devices connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(connectionManager.connectedDevices) { device in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.caption)
                            Text(device.platform.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var sessionsSection: some View {
        Section("Sessions") {
            if sessionListModel.activeSessions.isEmpty {
                Text("No active sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessionListModel.activeSessions) { session in
                    HStack {
                        Circle()
                            .fill(statusColor(for: session.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading) {
                            Text(session.projectName)
                                .font(.caption)
                                .lineLimit(1)
                            Text("\(session.messageCount) messages")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(session.lastActivityAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        if !connectionManager.isServerRunning {
            return "Server off"
        } else if connectionManager.connectedDevices.isEmpty {
            return "Listening"
        } else {
            let count = connectionManager.connectedDevices.count
            return "\(count) device\(count == 1 ? "" : "s")"
        }
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .active: return .green
        case .idle: return .yellow
        case .completed: return .gray
        case .error: return .red
        }
    }
}
