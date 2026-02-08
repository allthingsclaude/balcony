import SwiftUI

/// Renders parsed terminal conversation lines with a native input bar.
/// Keystrokes are streamed live to the Mac terminal as the user types.
struct ConversationView: View {
    let lines: [TerminalLine]
    var onSendInput: ((String) -> Void)?

    @State private var inputText = ""
    @State private var previousText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Conversation scroll area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            TerminalLineView(line: line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                }
                .onChange(of: lines.count) { _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .monospaced))
                    .focused($inputFocused)
                    .onSubmit { submitInput() }
                    .onChange(of: inputText) { newValue in
                        sendLiveKeystrokes(from: previousText, to: newValue)
                        previousText = newValue
                    }
                    .padding(.vertical, 8)

                Button(action: submitInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty ? .gray : .blue)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Scrolling

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let lastId = lines.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    // MARK: - Live Input

    /// Send the diff between old and new text as live keystrokes.
    private func sendLiveKeystrokes(from oldText: String, to newText: String) {
        if newText.hasPrefix(oldText) && newText.count > oldText.count {
            // Characters added at end — send just the new ones.
            let added = String(newText.dropFirst(oldText.count))
            onSendInput?(added)
        } else if oldText.hasPrefix(newText) && newText.count < oldText.count {
            // Characters deleted from end — send DEL (backspace).
            let deleteCount = oldText.count - newText.count
            onSendInput?(String(repeating: "\u{7f}", count: deleteCount))
        } else if oldText != newText {
            // Complex edit (autocorrect, paste, etc.) — clear old, send new.
            if !oldText.isEmpty {
                onSendInput?(String(repeating: "\u{7f}", count: oldText.count))
            }
            if !newText.isEmpty {
                onSendInput?(newText)
            }
        }
    }

    /// Submit the current input (send carriage return and clear).
    private func submitInput() {
        guard !inputText.isEmpty else { return }
        onSendInput?("\r")
        // Set previousText first so onChange doesn't send backspaces for the clear.
        previousText = ""
        inputText = ""
    }
}

// MARK: - Terminal Line View

/// Renders a single terminal line as styled text.
struct TerminalLineView: View {
    let line: TerminalLine

    var body: some View {
        if line.segments.isEmpty {
            Text(" ")
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 18)
        } else {
            buildAttributedText()
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func buildAttributedText() -> Text {
        var result = Text("")
        for segment in line.segments {
            let fgColor = ANSIColorMapper.color(for: segment.style.fgColor)
            var text = Text(segment.text)
                .foregroundColor(segment.style.isDim ? fgColor.opacity(0.6) : fgColor)
            if segment.style.isBold {
                text = text.bold()
            }
            if segment.style.isItalic {
                text = text.italic()
            }
            if segment.style.isUnderline {
                text = text.underline()
            }
            result = result + text
        }
        return result
    }
}
