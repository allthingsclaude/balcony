import SwiftUI
import BalconyShared

struct SessionListView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Connected Mac header
                    ConnectedMacHeaderView(
                        deviceName: connectionManager.connectedDevice?.name ?? "Mac"
                    )
                    .padding(.horizontal, BalconyTheme.spacingLG)
                    .padding(.top, BalconyTheme.spacingSM)

                    if sessionManager.sessions.isEmpty {
                        EmptySessionsView()
                            .padding(.top, 40)
                    } else {
                        // Stats row
                        SessionStatsView(sessions: sessionManager.sessions)
                            .padding(.horizontal, BalconyTheme.spacingLG)
                            .padding(.top, BalconyTheme.spacingLG)

                        // Grouped session sections
                        sessionSections
                    }
                }
                .padding(.bottom, 80)
            }
            .refreshable {
                await sessionManager.refreshSessions()
            }

            // Bottom fade
            BalconyTheme.bottomFadeGradient()
                .frame(height: 100)
                .allowsHitTesting(false)
        }
        .background(BalconyTheme.background)
        .navigationTitle("Sessions")
        .navigationDestination(for: Session.self) { session in
            TerminalContainerView(session: session)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    Task { await connectionManager.disconnect() }
                } label: {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    // MARK: - Grouped Sections

    @ViewBuilder
    private var sessionSections: some View {
        let active = sessionManager.sessions.filter { $0.status == .active }
        let idle = sessionManager.sessions.filter { $0.status == .idle }
        let completed = sessionManager.sessions.filter { $0.status == .completed || $0.status == .error }

        if !active.isEmpty {
            sessionSection(title: "ACTIVE", sessions: active, dimmed: false)
        }
        if !idle.isEmpty {
            sessionSection(title: "IDLE", sessions: idle, dimmed: false)
        }
        if !completed.isEmpty {
            sessionSection(title: "COMPLETED", sessions: completed, dimmed: true)
        }
    }

    private func sessionSection(title: String, sessions: [Session], dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: BalconyTheme.spacingSM) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(BalconyTheme.textSecondary)
                .padding(.horizontal, BalconyTheme.spacingLG)

            ForEach(sessions) { session in
                NavigationLink(value: session) {
                    SessionCardView(session: session, dimmed: dimmed)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, BalconyTheme.spacingLG)
            }
        }
        .padding(.top, BalconyTheme.spacingLG)
    }
}

// MARK: - Connected Mac Header

private struct ConnectedMacHeaderView: View {
    let deviceName: String

    var body: some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 20))
                .foregroundStyle(BalconyTheme.textPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(deviceName)
                    .font(BalconyTheme.headingFont(15))
                    .foregroundStyle(BalconyTheme.textPrimary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(BalconyTheme.statusGreen)
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.caption2)
                        .foregroundStyle(BalconyTheme.statusGreen)
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
    }
}

// MARK: - Session Stats

private struct SessionStatsView: View {
    let sessions: [Session]

    var body: some View {
        HStack(spacing: 0) {
            statItem(value: "\(sessions.count)", label: "Sessions")
            divider
            statItem(
                value: "\(sessions.filter { $0.status == .active }.count)",
                label: "Active"
            )
            divider
            statItem(
                value: "\(sessions.reduce(0) { $0 + $1.messageCount })",
                label: "Messages"
            )
        }
        .padding(.vertical, BalconyTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                .fill(BalconyTheme.surfaceSecondary)
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(BalconyTheme.headingFont(20))
                .foregroundStyle(BalconyTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(BalconyTheme.separator)
            .frame(width: 1, height: 28)
    }
}

// MARK: - Empty Sessions

private struct EmptySessionsView: View {
    var body: some View {
        VStack(spacing: BalconyTheme.spacingLG) {
            ZStack {
                Circle()
                    .fill(BalconyTheme.surfaceSecondary)
                    .frame(width: 64, height: 64)
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(BalconyTheme.textSecondary)
            }

            VStack(spacing: BalconyTheme.spacingSM) {
                Text("No Sessions Yet")
                    .font(BalconyTheme.headingFont(18))
                    .foregroundStyle(BalconyTheme.textPrimary)
                Text("Start a Claude Code session on your\nMac to see it here.")
                    .font(BalconyTheme.bodyFont(14))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Tip card
            HStack(spacing: BalconyTheme.spacingSM) {
                Image(systemName: "apple.terminal")
                    .font(.system(size: 14))
                    .foregroundColor(BalconyTheme.accent)
                Text("Run ")
                    .font(BalconyTheme.bodyFont(13))
                    .foregroundColor(BalconyTheme.textSecondary)
                + Text("claude")
                    .font(BalconyTheme.monoFont(13))
                    .foregroundColor(BalconyTheme.accent)
                + Text(" in your terminal to start")
                    .font(BalconyTheme.bodyFont(13))
                    .foregroundColor(BalconyTheme.textSecondary)
            }
            .padding(BalconyTheme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: BalconyTheme.radiusSM)
                    .fill(BalconyTheme.accentSubtle)
            )
        }
        .padding(.horizontal, BalconyTheme.spacingXL)
    }
}
