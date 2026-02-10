import SwiftUI
import BalconyShared

/// Main connected view with a sliding sidebar and terminal content area.
struct SidebarContainerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var isSidebarOpen = false
    @State private var selectedSession: Session?
    @State private var isLoading = false
    @State private var showingSettings = false
    @State private var showDisconnectConfirm = false
    @State private var dragOffset: CGFloat = 0

    private let sidebarWidthFraction: CGFloat = 0.69
    private let animationResponse: CGFloat = 0.35
    private let animationDamping: CGFloat = 0.85

    var body: some View {
        GeometryReader { geo in
            let sidebarWidth = geo.size.width * sidebarWidthFraction
            let windowInsets = (UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .safeAreaInsets) ?? .zero
            let safeTop = windowInsets.top
            let safeBottom = windowInsets.bottom

            ZStack(alignment: .leading) {
                // Full-width black so rounded corners on content always contrast
                Color.black.ignoresSafeArea()

                // MARK: - Sidebar (fixed underneath)
                SessionSidebarView(
                    selectedSessionId: selectedSession?.id,
                    onSelectSession: { session in
                        selectSession(session)
                        closeSidebar()
                    },
                    onSettings: {
                        closeSidebar()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showingSettings = true
                        }
                    },
                    onDisconnect: {
                        closeSidebar()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showDisconnectConfirm = true
                        }
                    },
                    safeAreaTop: safeTop,
                    safeAreaBottom: safeBottom
                )
                .frame(width: sidebarWidth)

                // MARK: - Main Content (slides right to reveal sidebar)
                mainContent
                    .frame(width: geo.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: isSidebarOpen || dragOffset > 0 ? 60 : 0, style: .continuous))
                    .offset(x: contentOffset(sidebarWidth: sidebarWidth))
                    .shadow(color: .black.opacity(isSidebarOpen || dragOffset > 0 ? 0.2 : 0), radius: 16, x: -5)
                    .disabled(isSidebarOpen)

                // MARK: - Tap-to-dismiss overlay
                if isSidebarOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .offset(x: contentOffset(sidebarWidth: sidebarWidth))
                        .onTapGesture { closeSidebar() }
                        .accessibilityLabel("Close sidebar")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .gesture(edgeSwipeGesture(sidebarWidth: sidebarWidth))
            .animation(
                .spring(response: animationResponse, dampingFraction: animationDamping),
                value: isSidebarOpen
            )
            .animation(
                .spring(response: animationResponse, dampingFraction: animationDamping),
                value: dragOffset
            )
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert("Disconnect?", isPresented: $showDisconnectConfirm) {
            Button("Disconnect", role: .destructive) {
                BalconyTheme.hapticMedium()
                Task { await connectionManager.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll return to the discovery screen.")
        }
        .onAppear {
            autoSelectSession()
        }
        .onChange(of: sessionManager.sessions) { _ in
            // Auto-select if nothing selected yet, or update the selected session's data
            if selectedSession == nil {
                autoSelectSession()
            } else if let selected = selectedSession,
                      let updated = sessionManager.sessions.first(where: { $0.id == selected.id }) {
                selectedSession = updated
            }
        }
    }

    // MARK: - Main Content Area

    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            ZStack {
                BalconyTheme.background.ignoresSafeArea()

                if let session = selectedSession {
                    Group {
                        if isLoading {
                            loadingView
                        } else {
                            ConversationView(
                                lines: sessionManager.conversationLines,
                                onSendInput: { text in
                                    Task {
                                        await sessionManager.sendInput(text, to: session)
                                    }
                                }
                            )
                        }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !connectionManager.isConnected {
                            connectionBanner
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: connectionManager.isConnected)
                    .navigationTitle(session.projectName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            sidebarButton
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            StatusBadge(status: sessionManager.activeSession?.status ?? session.status, compact: true)
                        }
                    }
                } else {
                    emptyContentState
                        .navigationTitle("Balcony")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                sidebarButton
                            }
                        }
                }
            }
        }
    }

    // MARK: - Sidebar Button

    private var sidebarButton: some View {
        Button {
            BalconyTheme.hapticLight()
            openSidebar()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BalconyTheme.textPrimary)
        }
        .accessibilityLabel("Open sidebar")
    }

    // MARK: - Connection Banner

    private var connectionBanner: some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            if connectionManager.isReconnecting {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
                Text("Reconnecting...")
                    .font(BalconyTheme.bodyFont(13))
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .fill(BalconyTheme.statusRed)
                    .frame(width: 8, height: 8)
                Text("Connection lost")
                    .font(BalconyTheme.bodyFont(13))
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(BalconyTheme.statusRed.opacity(0.9))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: connectionManager.isConnected)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: BalconyTheme.spacingMD) {
            ProgressView()
                .tint(BalconyTheme.accent)
            Text("Loading session...")
                .font(BalconyTheme.bodyFont(14))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    // MARK: - Empty Content State

    private var emptyContentState: some View {
        VStack(spacing: BalconyTheme.spacingLG) {
            Spacer()
            ZStack {
                Circle()
                    .fill(BalconyTheme.surfaceSecondary)
                    .frame(width: 64, height: 64)
                Image(systemName: "terminal")
                    .font(.system(size: 28))
                    .foregroundStyle(BalconyTheme.textSecondary)
            }
            VStack(spacing: BalconyTheme.spacingSM) {
                Text("No Session Selected")
                    .font(BalconyTheme.headingFont(18))
                    .foregroundStyle(BalconyTheme.textPrimary)
                Text("Open the sidebar to pick a session,\nor start one on your Mac.")
                    .font(BalconyTheme.bodyFont(14))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content Offset

    private func contentOffset(sidebarWidth: CGFloat) -> CGFloat {
        if isSidebarOpen {
            return sidebarWidth + min(0, dragOffset)
        } else {
            return max(0, dragOffset)
        }
    }

    // MARK: - Gestures

    private func edgeSwipeGesture(sidebarWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if isSidebarOpen {
                    // Swiping left to close
                    if value.translation.width < 0 {
                        dragOffset = value.translation.width
                    }
                } else {
                    // Swiping right to open — only from left edge
                    if value.startLocation.x < 30 && value.translation.width > 0 {
                        dragOffset = min(value.translation.width, sidebarWidth)
                    }
                }
            }
            .onEnded { value in
                if isSidebarOpen {
                    if value.translation.width < -60 || value.predictedEndTranslation.width < -100 {
                        isSidebarOpen = false
                    }
                } else {
                    if value.translation.width > 60 || value.predictedEndTranslation.width > 100 {
                        isSidebarOpen = true
                    }
                }
                dragOffset = 0
            }
    }

    // MARK: - Actions

    private func openSidebar() {
        isSidebarOpen = true
    }

    private func closeSidebar() {
        isSidebarOpen = false
    }

    private func selectSession(_ session: Session) {
        guard session.id != selectedSession?.id else { return }

        // Unsubscribe from old
        if let old = selectedSession {
            Task { await sessionManager.unsubscribe(from: old) }
        }

        selectedSession = session
        isLoading = true

        // Subscribe to new
        Task {
            await sessionManager.subscribe(to: session)
            isLoading = false
        }
    }

    /// Auto-select the first active session, or the most recently active one.
    private func autoSelectSession() {
        guard selectedSession == nil, !sessionManager.sessions.isEmpty else { return }
        let sorted = sessionManager.sessions.sorted { a, b in
            let orderA = statusPriority(a.status)
            let orderB = statusPriority(b.status)
            if orderA != orderB { return orderA < orderB }
            return a.lastActivityAt > b.lastActivityAt
        }
        if let best = sorted.first {
            selectSession(best)
        }
    }

    private func statusPriority(_ status: SessionStatus) -> Int {
        switch status {
        case .active: return 0
        case .idle: return 1
        case .completed: return 2
        case .error: return 3
        }
    }
}
