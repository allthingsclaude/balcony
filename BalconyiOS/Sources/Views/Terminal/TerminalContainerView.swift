import SwiftUI
import BalconyShared

struct TerminalContainerView: View {
    let session: Session
    @EnvironmentObject var sessionManager: SessionManager
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output area
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // TODO: Replace with SwiftTerm TerminalView via UIViewRepresentable
                    Text("Terminal output for session: \(session.id)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding()
                }
            }
            .background(.black)

            Divider()

            // Input composer
            InputComposerView(text: $inputText) {
                Task {
                    await sessionManager.sendInput(inputText, to: session)
                    inputText = ""
                }
            }
        }
        .navigationTitle(session.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await sessionManager.subscribe(to: session)
            }
        }
        .onDisappear {
            Task {
                await sessionManager.unsubscribe(from: session)
            }
        }
    }
}
