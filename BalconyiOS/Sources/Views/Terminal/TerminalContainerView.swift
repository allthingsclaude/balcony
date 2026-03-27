import SwiftUI
import UIKit
import BalconyShared

struct TerminalContainerView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if isLoading {
                // Loading state — shown briefly while history replay completes.
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
        .onAppear {
            Task {
                await sessionManager.subscribe(to: session)
                // Brief delay so history replay finishes before showing content.
                // Prevents the screen from jumping as chunks arrive.
                try? await Task.sleep(nanoseconds: 500_000_000)
                isLoading = false
            }
        }
        .onDisappear {
            Task { await sessionManager.unsubscribe(from: session) }
        }
    }
}
