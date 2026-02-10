import SwiftUI
import BalconyShared

/// The sidebar content panel showing sessions, connected Mac header, and actions.
struct SessionSidebarView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var connectionManager: ConnectionManager
    let selectedSessionId: String?
    let onSelectSession: (Session) -> Void
    let onSettings: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Connected Mac header
            ConnectedMacHeaderView(
                deviceName: connectionManager.connectedDevice?.name ?? "Mac"
            )
            .padding(.horizontal, BalconyTheme.spacingMD)
            .padding(.top, BalconyTheme.spacingMD)
            .padding(.bottom, BalconyTheme.spacingSM)

            Divider()
                .overlay(BalconyTheme.separator)

            // Session list
            if sortedSessions.isEmpty {
                sidebarEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sortedSessions) { session in
                            SidebarSessionRow(
                                session: session,
                                isSelected: session.id == selectedSessionId
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                BalconyTheme.hapticLight()
                                onSelectSession(session)
                            }
                        }
                    }
                    .padding(.vertical, BalconyTheme.spacingSM)
                    .padding(.horizontal, BalconyTheme.spacingSM)
                }
            }

            Spacer(minLength: 0)

            // Bottom actions
            VStack(spacing: 0) {
                Divider()
                    .overlay(BalconyTheme.separator)

                VStack(spacing: 2) {
                    // Settings
                    Button(action: onSettings) {
                        HStack(spacing: BalconyTheme.spacingSM) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                                .foregroundStyle(BalconyTheme.textSecondary)
                                .frame(width: 24)
                            Text("Settings")
                                .font(BalconyTheme.bodyFont(14))
                                .foregroundStyle(BalconyTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, BalconyTheme.spacingMD)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Disconnect
                    Button(action: onDisconnect) {
                        HStack(spacing: BalconyTheme.spacingSM) {
                            Image(systemName: "rectangle.portrait.and.arrow.forward")
                                .font(.system(size: 14))
                                .foregroundStyle(BalconyTheme.statusRed)
                                .rotationEffect(.degrees(180))
                                .frame(width: 24)
                            Text("Disconnect")
                                .font(BalconyTheme.bodyFont(14))
                                .foregroundStyle(BalconyTheme.statusRed)
                            Spacer()
                        }
                        .padding(.horizontal, BalconyTheme.spacingMD)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, BalconyTheme.spacingSM)
            }
        }
        .background(BalconyTheme.surface)
    }

    // MARK: - Sorted Sessions

    /// Active first, then idle, then completed/error, each group sorted by lastActivityAt descending.
    private var sortedSessions: [Session] {
        sessionManager.sessions.sorted { a, b in
            let orderA = statusOrder(a.status)
            let orderB = statusOrder(b.status)
            if orderA != orderB { return orderA < orderB }
            return a.lastActivityAt > b.lastActivityAt
        }
    }

    private func statusOrder(_ status: SessionStatus) -> Int {
        switch status {
        case .active: return 0
        case .idle: return 1
        case .completed: return 2
        case .error: return 3
        }
    }

    // MARK: - Empty State

    private var sidebarEmptyState: some View {
        VStack(spacing: BalconyTheme.spacingMD) {
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundStyle(BalconyTheme.textSecondary)
            Text("No sessions")
                .font(BalconyTheme.bodyFont(14))
                .foregroundStyle(BalconyTheme.textSecondary)
            Text("Start a Claude Code session\non your Mac")
                .font(BalconyTheme.bodyFont(12))
                .foregroundStyle(BalconyTheme.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Connected Mac Header (extracted from SessionListView)

struct ConnectedMacHeaderView: View {
    let deviceName: String

    var body: some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(BalconyTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 18))
                    .foregroundStyle(BalconyTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(BalconyTheme.headingFont(15))
                    .foregroundStyle(BalconyTheme.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(BalconyTheme.accent)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundStyle(BalconyTheme.accent)
                }
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .padding(BalconyTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                .fill(BalconyTheme.surfaceSecondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connected to \(deviceName)")
    }
}

// MARK: - Sidebar Session Row

/// Compact row for the sidebar session list.
struct SidebarSessionRow: View {
    let session: Session
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(avatarColor.opacity(isDimmed ? 0.1 : 0.15))
                    .frame(width: 34, height: 34)
                Text(projectInitial)
                    .font(BalconyTheme.headingFont(14))
                    .foregroundStyle(avatarColor.opacity(isDimmed ? 0.5 : 1))
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.projectName)
                        .font(BalconyTheme.headingFont(14))
                        .foregroundStyle(BalconyTheme.textPrimary)
                        .opacity(isDimmed ? 0.5 : 1)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    statusDot
                }

                HStack {
                    Text(abbreviatedPath)
                        .font(BalconyTheme.monoFont(10))
                        .foregroundStyle(BalconyTheme.textSecondary)
                        .opacity(isDimmed ? 0.4 : 0.7)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(session.lastActivityAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(BalconyTheme.textSecondary)
                        .opacity(isDimmed ? 0.4 : 0.7)
                }
            }
        }
        .padding(.horizontal, BalconyTheme.spacingSM)
        .padding(.vertical, BalconyTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: BalconyTheme.radiusSM)
                .fill(isSelected ? BalconyTheme.accent.opacity(0.15) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.projectName), \(session.status.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Helpers

    private var isDimmed: Bool {
        session.status == .completed || session.status == .error
    }

    private var projectInitial: String {
        String(session.projectName.prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        switch session.status {
        case .active: return BalconyTheme.accent
        case .idle: return BalconyTheme.statusYellow
        case .completed: return BalconyTheme.textSecondary
        case .error: return BalconyTheme.statusRed
        }
    }

    private var abbreviatedPath: String {
        let path = session.projectPath
        if let homeRange = path.range(of: "/Users/") {
            let afterUsers = path[homeRange.upperBound...]
            if let slashIdx = afterUsers.firstIndex(of: "/") {
                return "~" + String(afterUsers[slashIdx...])
            }
        }
        return path
    }

    private var statusDot: some View {
        Circle()
            .fill(avatarColor)
            .frame(width: 7, height: 7)
    }
}
