import SwiftUI
import BalconyShared

/// Main connected view with a sliding sidebar and terminal content area.
struct SidebarContainerView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @Environment(\.colorScheme) private var colorScheme
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
                BalconyTheme.sidebarBackground.ignoresSafeArea()

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
                .scaleEffect(sidebarScale(sidebarWidth: sidebarWidth), anchor: .leading)
                .opacity(sidebarOpacity(sidebarWidth: sidebarWidth))

                // MARK: - Main Content (slides right to reveal sidebar)
                mainContent
                    .frame(width: geo.size.width)
                    .clipShape(RoundedRectangle(cornerRadius: isSidebarOpen || dragOffset > 0 ? 60 : 0, style: .continuous))
                    .offset(x: contentOffset(sidebarWidth: sidebarWidth))
                    .shadow(color: .black.opacity(isSidebarOpen || dragOffset > 0 ? (colorScheme == .dark ? 0.2 : 0.08) : 0), radius: 16, x: -5)
                    .disabled(isSidebarOpen)

                // MARK: - Edge drag zone (beats ScrollView gestures)
                if !isSidebarOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .ignoresSafeArea()
                        .highPriorityGesture(
                            edgeDragGesture(sidebarWidth: sidebarWidth)
                        )
                }

                // MARK: - Tap-to-dismiss overlay
                if isSidebarOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .offset(x: contentOffset(sidebarWidth: sidebarWidth))
                        .onTapGesture { closeSidebar() }
                        .highPriorityGesture(
                            edgeSwipeGesture(sidebarWidth: sidebarWidth)
                        )
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
            Button("Cancel", role: .cancel) {}
            Button("Disconnect") {
                BalconyTheme.hapticMedium()
                Task { await connectionManager.disconnect() }
            }
        } message: {
            Text("You'll return to the discovery screen.")
        }
        .onAppear {
            autoSelectSession()
            // Open sidebar immediately when no session is selected
            if selectedSession == nil {
                isSidebarOpen = true
            }
        }
        .onChange(of: sessionManager.sessions) { _ in
            // Auto-select if nothing selected yet, or update the selected session's data
            if selectedSession == nil {
                autoSelectSession()
                // Open sidebar when sessions arrive but none selected
                if selectedSession == nil && !isSidebarOpen {
                    isSidebarOpen = true
                }
            } else if let selected = selectedSession,
                      let updated = sessionManager.sessions.first(where: { $0.id == selected.id }) {
                selectedSession = updated
            } else if let selected = selectedSession,
                      !sessionManager.sessions.contains(where: { $0.id == selected.id }) {
                // Active session was removed (CLI exited) — clear selection and show sidebar
                selectedSession = nil
                isSidebarOpen = true
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
                                slashCommands: sessionManager.slashCommands,
                                projectFiles: sessionManager.projectFiles,
                                activePrompt: sessionManager.activePrompt,
                                pendingHookData: sessionManager.pendingHookData,
                                pendingIdlePrompt: sessionManager.pendingIdlePrompt,
                                pendingInputText: sessionManager.pendingInputText,
                                availableSessions: sessionManager.availableSessions,
                                showSessionPicker: sessionManager.showSessionPicker,
                                availableModels: sessionManager.availableModels,
                                currentModelId: sessionManager.currentModelId,
                                showModelPicker: sessionManager.showModelPicker,
                                rewindTurns: sessionManager.rewindTurns,
                                showRewindPicker: sessionManager.showRewindPicker,
                                pendingAskUserQuestion: sessionManager.pendingAskUserQuestion,
                                onSendInput: { text in
                                    Task {
                                        await sessionManager.sendInput(text, to: session)
                                    }
                                },
                                onSubmitAskUserQuestion: { answers in
                                    Task { await sessionManager.submitAskUserQuestionResponse(answers: answers) }
                                },
                                onDismissAskUserQuestion: {
                                    sessionManager.dismissAskUserQuestion()
                                },
                                onSelectSession: { session in
                                    Task {
                                        await sessionManager.selectSession(session)
                                    }
                                },
                                onRequestSessionPicker: {
                                    Task {
                                        await sessionManager.requestSessionPicker()
                                    }
                                },
                                onDismissSessionPicker: {
                                    sessionManager.dismissSessionPicker()
                                },
                                onSelectModel: { model in
                                    Task {
                                        await sessionManager.selectModel(model)
                                    }
                                },
                                onRequestModelPicker: {
                                    Task {
                                        await sessionManager.requestModelPicker()
                                    }
                                },
                                onDismissModelPicker: {
                                    sessionManager.dismissModelPicker()
                                },
                                onSelectRewind: { turn in
                                    Task { await sessionManager.selectRewind(turn) }
                                },
                                onRequestRewind: {
                                    sessionManager.showRewind()
                                },
                                onDismissRewindPicker: {
                                    sessionManager.dismissRewindPicker()
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
                            sidebarButtonWithIndicator
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            EscButton {
                                Task {
                                    await sessionManager.sendInput("\u{1B}", to: session)
                                }
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            } onDoubleTap: {
                                sessionManager.showRewind()
                            }
                        }
                    }
                } else {
                    emptyContentState
                        .navigationTitle("Balcony")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                sidebarButtonWithIndicator
                            }
                        }
                }
            }
        }
        .overlayPreferenceValue(SidebarButtonAnchorKey.self) { anchor in
            if let anchor {
                GeometryReader { geo in
                    let point = geo[anchor]
                    ZStack {
                        if hasOtherSessionActivity {
                            SidebarActivityDot(pulsing: otherSessionNeedsAttention)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .position(x: point.x - 0, y: point.y - 15)
                    .animation(.easeOut(duration: 0.3), value: hasOtherSessionActivity)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Sidebar Button

    /// Whether any session other than the currently selected one needs attention.
    private var hasOtherSessionActivity: Bool {
        sessionManager.sessions.contains { session in
            session.id != selectedSession?.id && (session.needsAttention || session.awaitingInput)
        }
    }

    /// Whether the activity comes from a session needing attention (vs just awaiting input).
    private var otherSessionNeedsAttention: Bool {
        sessionManager.sessions.contains { session in
            session.id != selectedSession?.id && session.needsAttention
        }
    }

    private var sidebarButtonWithIndicator: some View {
        Button {
            BalconyTheme.hapticLight()
            openSidebar()
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BalconyTheme.textPrimary)
        }
        .accessibilityLabel("Open sidebar")
        .anchorPreference(key: SidebarButtonAnchorKey.self, value: .trailing) { $0 }
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
        VStack(spacing: BalconyTheme.spacingMD) {
            Image(systemName: "arrow.left.to.line")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(BalconyTheme.textSecondary.opacity(0.5))
            Text("Select a session")
                .font(BalconyTheme.bodyFont(15))
                .foregroundStyle(BalconyTheme.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BalconyTheme.surfaceSecondary.opacity(0.5))
    }

    // MARK: - Content Offset & Sidebar Transform

    private func contentOffset(sidebarWidth: CGFloat) -> CGFloat {
        if isSidebarOpen {
            return sidebarWidth + min(0, dragOffset)
        } else {
            return max(0, dragOffset)
        }
    }

    /// Fraction of sidebar reveal (0 = fully hidden, 1 = fully open).
    private func revealFraction(sidebarWidth: CGFloat) -> CGFloat {
        guard sidebarWidth > 0 else { return 0 }
        return contentOffset(sidebarWidth: sidebarWidth) / sidebarWidth
    }

    /// Sidebar scales from 0.92 → 1.0 as it reveals.
    private func sidebarScale(sidebarWidth: CGFloat) -> CGFloat {
        let fraction = revealFraction(sidebarWidth: sidebarWidth)
        return 0.95 + 0.05 * fraction
    }

    /// Sidebar fades from 0.5 → 1.0 as it reveals.
    private func sidebarOpacity(sidebarWidth: CGFloat) -> CGFloat {
        let fraction = revealFraction(sidebarWidth: sidebarWidth)
        return 0.5 + 0.5 * fraction
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
                    // Swiping right to open — from anywhere on the content
                    if value.translation.width > 0 {
                        dragOffset = min(value.translation.width, sidebarWidth)
                    }
                }
            }
            .onEnded { value in
                let fromEdge = value.startLocation.x < 40
                if isSidebarOpen {
                    if value.translation.width < -60 || value.predictedEndTranslation.width < -100 {
                        isSidebarOpen = false
                    }
                } else {
                    // Lower threshold for edge swipes so they feel more reliable
                    let distanceThreshold: CGFloat = fromEdge ? 30 : 60
                    let predictedThreshold: CGFloat = fromEdge ? 50 : 100
                    if value.translation.width > distanceThreshold || value.predictedEndTranslation.width > predictedThreshold {
                        isSidebarOpen = true
                    }
                }
                dragOffset = 0
            }
    }

    /// Edge-only drag with low minimum distance — always beats ScrollView.
    private func edgeDragGesture(sidebarWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if value.translation.width > 0 {
                    dragOffset = min(value.translation.width, sidebarWidth)
                }
            }
            .onEnded { value in
                if value.translation.width > 30 || value.predictedEndTranslation.width > 50 {
                    isSidebarOpen = true
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

        // Set session first so sidebarWidthFraction updates, then close
        selectedSession = session
        isLoading = true
        closeSidebar()

        // Subscribe to new
        Task {
            await sessionManager.subscribe(to: session)
            isLoading = false
        }
    }

    /// Auto-select a session only when there's exactly one.
    /// When multiple sessions exist, leave the sidebar open for the user to choose.
    private func autoSelectSession() {
        guard selectedSession == nil, !sessionManager.sessions.isEmpty else { return }
        if sessionManager.sessions.count == 1, let only = sessionManager.sessions.first {
            selectSession(only)
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

// MARK: - Sidebar Activity Dot

/// Small orange indicator next to the hamburger icon, matching the 7pt sidebar dot.
private struct SidebarActivityDot: View {
    let pulsing: Bool
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(BalconyTheme.accent)
            .frame(width: 7, height: 7)
            .opacity(pulsing && isPulsing ? 0.3 : 1.0)
            .onChange(of: pulsing) { newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPulsing = false
                    }
                }
            }
            .onAppear {
                if pulsing {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Anchor Preference Key

private struct SidebarButtonAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

