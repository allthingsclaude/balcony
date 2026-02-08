import SwiftUI
import SwiftTerm

/// A SwiftUI wrapper around SwiftTerm's `TerminalView` for displaying raw PTY terminal output.
///
/// This view does not run a local process — it receives raw byte arrays via `feed(byteArray:)` from the
/// session manager and forwards any keyboard input back through the `onInput` callback.
struct TerminalViewRepresentable: UIViewRepresentable {
    /// Raw byte chunks to feed into the terminal.
    let rawFeedContent: [[UInt8]]
    /// Called when the user types into the terminal.
    var onInput: ((String) -> Void)?
    /// Called when the terminal view resizes.
    var onResize: ((Int, Int) -> Void)?

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = .init(white: 0.9, alpha: 1.0)
        view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.terminalDelegate = context.coordinator
        context.coordinator.rawFedCount = 0
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Keep coordinator closures current across SwiftUI view updates
        context.coordinator.onInput = onInput
        context.coordinator.onResize = onResize

        let alreadyFed = context.coordinator.rawFedCount
        if rawFeedContent.count > alreadyFed {
            for bytes in rawFeedContent[alreadyFed...] {
                uiView.feed(byteArray: ArraySlice(bytes))
            }
            context.coordinator.rawFedCount = rawFeedContent.count
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, TerminalViewDelegate {
        var onInput: ((String) -> Void)?
        var onResize: ((Int, Int) -> Void)?
        /// Tracks how many rawFeedContent entries have been fed.
        var rawFedCount = 0

        init(onInput: ((String) -> Void)?, onResize: ((Int, Int) -> Void)?) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard let str = String(bytes: data, encoding: .utf8) else { return }
            onInput?(str)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize?(newCols, newRows)
        }

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
