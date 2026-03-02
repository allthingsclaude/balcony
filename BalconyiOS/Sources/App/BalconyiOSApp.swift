import SwiftUI
import BalconyShared

@main
struct BalconyiOSApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var sessionManager = SessionManager()
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("appIcon") private var appIcon: String = "light"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(sessionManager)
                .tint(BalconyTheme.accent)
                .onAppear {
                    sessionManager.configure(connectionManager: connectionManager)
                    applyAppearance(appearance)
                    applyIcon(appIcon)
                }
                .onChange(of: appearance) { newValue in
                    applyAppearance(newValue)
                }
                .onChange(of: appIcon) { newValue in
                    applyIcon(newValue)
                }
        }
    }

    private func applyAppearance(_ value: String) {
        let style: UIUserInterfaceStyle
        switch value {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified
        }
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }

    private func applyIcon(_ value: String) {
        let iconName = value == "dark" ? "AppIcon-Dark" : "AppIcon-Light"
        if UIApplication.shared.alternateIconName != iconName {
            UIApplication.shared.setAlternateIconName(iconName)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showConnected = false

    var body: some View {
        ZStack {
            // Actual app content (always fully laid out, hidden behind launch screen)
            ZStack {
                NavigationStack {
                    DiscoveryView()
                }
                .opacity(showConnected ? 0 : 1)
                .offset(x: showConnected ? -40 : 0)

                if showConnected {
                    SidebarContainerView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .overlay {
                if connectionManager.isReconnecting && !showConnected {
                    ReconnectingOverlay()
                }
            }

            // Launch screen overlay (always in tree, animates itself out)
            LaunchScreenView()
                .zIndex(1)
        }
        .background(BalconyTheme.background.ignoresSafeArea())
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showConnected)
        .onChange(of: connectionManager.isConnected) { connected in
            showConnected = connected
        }
    }
}

// MARK: - Launch Screen

private struct LaunchScreenView: View {
    @State private var dismissed = false

    var body: some View {
        ZStack {
            BalconyTheme.background.ignoresSafeArea()

            Image("BalconyLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 160)
        }
        .scaleEffect(dismissed ? 1.15 : 1)
        .opacity(dismissed ? 0 : 1)
        .allowsHitTesting(!dismissed)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(.easeOut(duration: 0.5)) {
                    dismissed = true
                }
            }
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
