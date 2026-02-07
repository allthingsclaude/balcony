import SwiftUI
import SwiftTerm

/// A SwiftUI wrapper around SwiftTerm's `TerminalView` for displaying ANSI terminal output.
///
/// This view does not run a local process — it receives text via `feed(text:)` from the
/// session manager and forwards any keyboard input back through the `onInput` callback.
struct TerminalViewRepresentable: UIViewRepresentable {
    /// Text chunks to feed into the terminal. Each new entry is appended.
    let feedContent: [String]
    /// Called when the user types into the terminal.
    var onInput: ((String) -> Void)?

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .init(white: 0.9, alpha: 1.0)
        view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.terminalDelegate = context.coordinator
        context.coordinator.fedCount = 0
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Feed only new content that hasn't been fed yet
        let alreadyFed = context.coordinator.fedCount
        if feedContent.count > alreadyFed {
            for text in feedContent[alreadyFed...] {
                uiView.feed(text: text)
            }
            context.coordinator.fedCount = feedContent.count
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, TerminalViewDelegate {
        var onInput: ((String) -> Void)?
        /// Tracks how many feedContent entries have been fed to avoid duplicates.
        var fedCount = 0

        init(onInput: ((String) -> Void)?) {
            self.onInput = onInput
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard let str = String(bytes: data, encoding: .utf8) else { return }
            onInput?(str)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
        }
    }
}
