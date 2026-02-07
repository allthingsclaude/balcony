import SwiftUI
import BalconyShared

struct TerminalContainerView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output area with tool use cards overlay
            ZStack(alignment: .bottom) {
                TerminalViewRepresentable(
                    feedContent: sessionManager.terminalFeed
                ) { userInput in
                    Task {
                        await sessionManager.sendInput(userInput, to: session)
                    }
                }
                .ignoresSafeArea(.container, edges: .bottom)

                // Pending tool use card shown as an overlay at bottom
                if let pendingTool = sessionManager.pendingToolUse {
                    ToolUseCard(toolUse: pendingTool)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            Divider()

            // Input composer
            InputComposerView(
                text: $inputText,
                showQuickActions: sessionManager.activeSession?.status == .waitingForInput,
                onApprove: {
                    Task { await sessionManager.sendInput("y", to: session) }
                },
                onDeny: {
                    Task { await sessionManager.sendInput("n", to: session) }
                },
                onSend: {
                    guard !inputText.isEmpty else { return }
                    Task {
                        await sessionManager.sendInput(inputText, to: session)
                        inputText = ""
                    }
                }
            )
        }
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                StatusBadge(status: sessionManager.activeSession?.status ?? session.status)
            }
        }
        .onAppear {
            Task { await sessionManager.subscribe(to: session) }
        }
        .onDisappear {
            Task { await sessionManager.unsubscribe(from: session) }
        }
    }
}
