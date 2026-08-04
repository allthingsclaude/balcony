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

    /// Row background on hover.
    static let rowHover = Color(nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.07)
                : NSColor(white: 0.0, alpha: 0.05)
        }
    ))
}

// MARK: - Session Attention State

/// How badly a session wants the user, derived live from `HookEventHandler`.
///
/// Read straight from the hook handler rather than from `Session.needsAttention`
/// / `awaitingInput`, which are only refreshed on the session poll timer (10s by
/// default) and would leave the menu bar showing a stale state for that long.
private enum SessionAttentionState {
    /// A permission request or question is blocking Claude.
    case needsAttention
    /// Claude finished its turn and is waiting for the next prompt.
    case awaitingInput
    /// Claude is mid-turn — nothing is required of the user.
    case working

    /// Sort rank; lower sorts first.
    var rank: Int {
        switch self {
        case .needsAttention: return 0
        case .awaitingInput: return 1
        case .working: return 2
        }
    }

    var label: String {
        switch self {
        case .needsAttention: return "needs you"
        case .awaitingInput: return "your turn"
        case .working: return "working"
        }
    }

    /// Deepest brand tone for the most urgent state, muted grey for the least,
    /// so urgency reads as intensity within the existing terracotta palette.
    var color: Color {
        switch self {
        case .needsAttention: return MenuBarTheme.brandDark
        case .awaitingInput: return MenuBarTheme.brand
        case .working: return .secondary
        }
    }

    var help: String {
        switch self {
        case .needsAttention: return "Open the pending request"
        case .awaitingInput: return "Reply to this session"
        case .working: return "Focus this session's terminal"
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @ObservedObject var updaterService: UpdaterService

    /// Called with a PTY session ID when the user clicks a session row.
    let onSelectSession: (String) -> Void

    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var sessionListModel: SessionListModel
    @EnvironmentObject private var hookEventHandler: HookEventHandler
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
        VStack(alignment: .leading, spacing: 2) {
            if sessionListModel.sessions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else {
                ForEach(prioritizedSessions, id: \.session.id) { entry in
                    SessionRow(session: entry.session, state: entry.state) {
                        select(entry.session.id)
                    }
                }
            }
        }
    }

    /// Sessions ranked by how much they want the user, most-recent first within
    /// each rank. `sorted(by:)` is not guaranteed stable, so recency is an
    /// explicit tiebreak rather than an assumption about the input order.
    private var prioritizedSessions: [(session: Session, state: SessionAttentionState)] {
        sessionListModel.sessionsByActivity
            .map { (session: $0, state: attentionState(for: $0.id)) }
            .sorted { lhs, rhs in
                if lhs.state.rank != rhs.state.rank {
                    return lhs.state.rank < rhs.state.rank
                }
                return lhs.session.lastActivityAt > rhs.session.lastActivityAt
            }
    }

    private func attentionState(for ptySessionId: String) -> SessionAttentionState {
        if hookEventHandler.hasAttentionNeeded(forPTYSession: ptySessionId) { return .needsAttention }
        if hookEventHandler.hasIdlePrompt(forPTYSession: ptySessionId) { return .awaitingInput }
        return .working
    }

    /// Dismiss the popover, then reveal the session.
    ///
    /// Closing first matters: the reveal activates a panel or another app, and
    /// doing that while the popover is still key leaves it stranded on screen.
    /// The hop to the next runloop turn lets the popover finish tearing down.
    private func select(_ ptySessionId: String) {
        NSApp.keyWindow?.close()
        DispatchQueue.main.async {
            onSelectSession(ptySessionId)
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
                // Capture the popover synchronously, before SettingsLink's own
                // action opens the Settings window and steals key status — by
                // the time the async block below runs, `NSApp.keyWindow` would
                // be the Settings window itself, so closing it there closed the
                // window we'd just opened instead of the popover.
                let popover = NSApp.keyWindow
                DispatchQueue.main.async {
                    popover?.close()
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

}

// MARK: - Session Row

/// One clickable session in the menu bar list.
private struct SessionRow: View {
    let session: Session
    let state: SessionAttentionState
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                StateDot(state: state)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.caption)
                        .lineLimit(1)
                    Text("\(session.messageCount) messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(state.label)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(state.color)
                    Text(session.lastActivityAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? MenuBarTheme.rowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .help(state.help)
        .accessibilityLabel("\(session.projectName), \(state.label)")
    }
}

// MARK: - State Dot

/// Status dot. Pulses only while Claude is working, so motion means "running".
private struct StateDot: View {
    let state: SessionAttentionState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    private var shouldPulse: Bool {
        guard case .working = state else { return false }
        return !reduceMotion
    }

    /// Scoped to `dimmed` alone, and deliberately *not* a bare `withAnimation`
    /// inside `onAppear`: that sets the animation for the whole transaction, and
    /// the popover's first layout is part of that transaction. Attaching a
    /// `.repeatForever` curve to it made the entire window animate in from the
    /// top-left corner on every open.
    private var pulse: Animation? {
        shouldPulse ? .easeInOut(duration: 0.95).repeatForever(autoreverses: true) : nil
    }

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: 7, height: 7)
            .overlay {
                if case .needsAttention = state {
                    Circle()
                        .stroke(state.color.opacity(0.3), lineWidth: 3)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 12, height: 12)
            .opacity(dimmed ? 0.35 : 1)
            .animation(pulse, value: dimmed)
            .onAppear { dimmed = shouldPulse }
            .onDisappear { dimmed = false }
    }
}
