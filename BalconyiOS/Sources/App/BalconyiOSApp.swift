import SwiftUI
import BalconyShared

@main
struct BalconyiOSApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(sessionManager)
                .tint(BalconyTheme.accent)
                .onAppear {
                    sessionManager.configure(connectionManager: connectionManager)
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showSessions = false

    var body: some View {
        NavigationStack {
            ZStack {
                DiscoveryView()
                    .opacity(showSessions ? 0 : 1)
                    .offset(x: showSessions ? -40 : 0)

                if showSessions {
                    SessionListView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay {
                if connectionManager.isReconnecting {
                    ReconnectingOverlay()
                }
            }
        }
        .background(BalconyTheme.background)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showSessions)
        .onChange(of: connectionManager.isConnected) { connected in
            showSessions = connected
        }
    }
}

// MARK: - Reconnecting Overlay

private struct ReconnectingOverlay: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: BalconyTheme.spacingLG) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 32))
                    .foregroundStyle(BalconyTheme.accent)
                    .scaleEffect(pulse ? 1.1 : 0.9)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: pulse
                    )

                VStack(spacing: BalconyTheme.spacingSM) {
                    Text("Reconnecting...")
                        .font(BalconyTheme.headingFont(18))
                        .foregroundStyle(BalconyTheme.textPrimary)
                    Text("Trying to reach your Mac")
                        .font(BalconyTheme.bodyFont(14))
                        .foregroundStyle(BalconyTheme.textSecondary)
                }

                Button {
                    Task { await connectionManager.disconnect() }
                } label: {
                    Text("Disconnect")
                        .font(BalconyTheme.bodyFont(15))
                        .fontWeight(.medium)
                        .foregroundStyle(BalconyTheme.statusRed)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                }
                .modifier(LiquidGlassCapsule())
            }
            .padding(BalconyTheme.spacingXL)
            .background(
                RoundedRectangle(cornerRadius: BalconyTheme.radiusLG)
                    .fill(BalconyTheme.surface)
                    .shadow(color: .black.opacity(0.2), radius: 20)
            )
        }
        .onAppear { pulse = true }
        .transition(.opacity)
    }
}
