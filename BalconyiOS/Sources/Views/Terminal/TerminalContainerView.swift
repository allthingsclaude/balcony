import SwiftUI
import BalconyShared

struct TerminalContainerView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        ConversationView(
            lines: sessionManager.conversationLines,
            onSendInput: { text in
                Task {
                    await sessionManager.sendInput(text, to: session)
                }
            }
        )
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
