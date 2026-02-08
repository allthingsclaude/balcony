import SwiftUI
import BalconyShared

struct TerminalContainerView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        TerminalViewRepresentable(
            rawFeedContent: sessionManager.terminalRawFeed,
            onInput: { userInput in
                Task {
                    await sessionManager.sendInput(userInput, to: session)
                }
            },
            onResize: { cols, rows in
                Task {
                    await sessionManager.sendResize(
                        cols: UInt16(cols),
                        rows: UInt16(rows),
                        to: session
                    )
                }
            }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green, in: Capsule())
                    StatusBadge(status: sessionManager.activeSession?.status ?? session.status)
                }
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
