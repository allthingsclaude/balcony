import SwiftUI
import BalconyShared

struct TerminalContainerView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if isLoading {
                // Loading state
                VStack(spacing: BalconyTheme.spacingMD) {
                    ProgressView()
                        .tint(BalconyTheme.accent)
                    Text("Loading session...")
                        .font(BalconyTheme.bodyFont(14))
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BalconyTheme.background)
                .transition(.opacity)
            } else {
                ConversationView(
                    lines: sessionManager.conversationLines,
                    slashCommands: sessionManager.slashCommands,
                    activePrompt: sessionManager.activePrompt,
                    onSendInput: { text in
                        Task {
                            await sessionManager.sendInput(text, to: session)
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !connectionManager.isConnected {
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
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: connectionManager.isConnected)
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                StatusBadge(status: sessionManager.activeSession?.status ?? session.status)
            }
        }
        .onAppear {
            Task {
                await sessionManager.subscribe(to: session)
                isLoading = false
            }
        }
        .onDisappear {
            Task { await sessionManager.unsubscribe(from: session) }
        }
    }
}
