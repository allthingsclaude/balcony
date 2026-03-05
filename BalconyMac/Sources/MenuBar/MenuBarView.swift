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
    @ObservedObject var updaterService: UpdaterService
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var sessionListModel: SessionListModel
    @State private var showingQRCode = false

    var body: some View {
        Group {
            if showingQRCode {
                qrCodeSection
            } else {
                mainContent
            }
        }
        .animation(.none, value: showingQRCode)
    }

    private var mainContent: some View {
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

            Button(action: { updaterService.checkForUpdates() }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Check for Updates")
            .focusable(false)
            .disabled(!updaterService.canCheckForUpdates)

            Button(action: { showingQRCode = true }) {
                Image(systemName: "qrcode")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Pair New Device")
            .focusable(false)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.caption)
            }
            .simultaneousGesture(TapGesture().onEnded {
                DispatchQueue.main.async {
                    NSApp.keyWindow?.close()
                    NSApp.activate(ignoringOtherApps: true)
                }
            })
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
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

    // MARK: - QR Code

    @State private var pairingURL: String?
    @State private var pairingError: String?

    private var qrCodeSection: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: { showingQRCode = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption2)
                        Text("Back")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.trailing, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .focusable(false)

                Spacer()
            }

            if let url = pairingURL {
                QRCodeView(pairingURL: url)
            } else if let error = pairingError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            } else {
                ProgressView("Generating pairing code...")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(MenuBarTheme.background)
        .task(id: showingQRCode) {
            guard showingQRCode, pairingURL == nil else { return }
            do {
                pairingURL = try await connectionManager.generatePairingURL()
            } catch {
                pairingError = "Failed to generate pairing code: \(error.localizedDescription)"
            }
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
