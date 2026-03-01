import SwiftUI
import BalconyShared

// MARK: - Menu Bar Theme

/// Brand-consistent colors for the menu bar popover, matching PanelTheme.
private enum MenuBarTheme {
    /// Primary brand — terracotta orange (#D97757)
    static let brand = Color(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x57/255.0)
    /// Darker brand variant (#B85A3A)
    static let brandDark = Color(red: 0xB8/255.0, green: 0x5A/255.0, blue: 0x3A/255.0)
    /// Lighter brand variant (#F0C4AE)
    static let brandLight = Color(red: 0xF0/255.0, green: 0xC4/255.0, blue: 0xAE/255.0)

    /// Warm popover background — light: #FAF8F4 @ 50%, dark: #191814 @ 30%
    static let background = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0x19/255.0, green: 0x18/255.0, blue: 0x14/255.0, alpha: 0.3)
                : NSColor(red: 0xFA/255.0, green: 0xF8/255.0, blue: 0xF4/255.0, alpha: 0.5)
        }
    ))
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var sessionListModel: SessionListModel
    @State private var showingQRCode = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection

            Divider()

            // Active Sessions
            sessionsSection

            Divider()

            // Connected Devices
            devicesSection

            Divider()

            // Footer
            footerSection
        }
        .padding(16)
        .frame(width: 320)
        .background(MenuBarTheme.background)
        .sheet(isPresented: $showingQRCode) {
            QRCodePairingView(connectionManager: connectionManager)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Claude Balcony")
                .font(.headline)
            Spacer()
            Text(statusText)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(statusBadgeColor.opacity(0.15))
                .foregroundStyle(statusBadgeColor)
                .clipShape(Capsule())
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sessionListModel.activeSessions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(sessionListModel.activeSessions) { session in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor(for: session.status))
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
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
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if connectionManager.connectedDevices.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "iphone.slash")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("No devices connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(connectionManager.connectedDevices) { device in
                    HStack(spacing: 8) {
                        Image(systemName: "iphone")
                            .font(.caption)
                            .foregroundStyle(MenuBarTheme.brand)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .font(.caption)
                            Text(device.platform.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            Task {
                                await connectionManager.disconnectDevice(device.id)
                            }
                        }) {
                            Image(systemName: "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Disconnect")
                        .focusable(false)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Spacer()

            Button(action: { showingQRCode = true }) {
                Image(systemName: "qrcode")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Pair New Device")
            .focusable(false)

            Button(action: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }) {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Preferences")
            .focusable(false)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .focusable(false)
        }
    }

    // MARK: - Helpers

    private var statusText: String {
        if !connectionManager.isServerRunning {
            return "Offline"
        } else if connectionManager.connectedDevices.isEmpty {
            return "Listening"
        } else {
            let count = connectionManager.connectedDevices.count
            return "\(count) device\(count == 1 ? "" : "s")"
        }
    }

    private var statusBadgeColor: Color {
        if !connectionManager.isServerRunning {
            return MenuBarTheme.brandDark
        } else if !connectionManager.connectedDevices.isEmpty {
            return MenuBarTheme.brand
        } else {
            return MenuBarTheme.brandLight
        }
    }

    private func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .active: return MenuBarTheme.brand
        case .idle: return MenuBarTheme.brandLight
        case .completed: return .gray
        case .error: return MenuBarTheme.brandDark
        }
    }
}
