import SwiftUI
import BalconyShared

struct SessionListView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        List {
            if sessionManager.sessions.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "No Active Sessions",
                        systemImage: "terminal",
                        description: Text("Start a Claude Code session on your Mac to see it here.")
                    )
                } else {
                    Text("No Active Sessions")
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
            } else {
                ForEach(sessionManager.sessions) { session in
                    NavigationLink(value: session) {
                        SessionRowView(session: session)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BalconyTheme.background)
        .navigationTitle("Sessions")
        .navigationDestination(for: Session.self) { session in
            TerminalContainerView(session: session)
        }
        .refreshable {
            await sessionManager.refreshSessions()
        }
    }
}
