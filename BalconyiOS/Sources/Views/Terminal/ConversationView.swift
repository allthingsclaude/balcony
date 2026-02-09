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
                        ForEach(groupedBlocks, id: \.id) { block in
                            switch block {
                            case .line(let line):
                                TerminalLineView(line: line)
                                    .id(line.id)
                            case .table(let rows):
                                ScrollView(.horizontal, showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(rows) { row in
                                            buildStyledText(from: row.segments)
                                                .font(.system(size: 13, design: .monospaced))
                                        }
                                    }
                                }
                                .id(rows.first?.id ?? -1)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
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
    // MARK: - Table Grouping

    private enum ConversationBlock {
        case line(TerminalLine)
        case table([TerminalLine])

        var id: Int {
            switch self {
            case .line(let l): return l.id
            case .table(let rows): return rows.first?.id ?? -1
            }
        }
    }

    /// Group consecutive table rows so they share a single horizontal scroll view.
    private var groupedBlocks: [ConversationBlock] {
        var blocks: [ConversationBlock] = []
        var tableBuffer: [TerminalLine] = []

        for line in lines {
            if line.isTableRow {
                tableBuffer.append(line)
            } else {
                if !tableBuffer.isEmpty {
                    blocks.append(.table(tableBuffer))
                    tableBuffer = []
                }
                blocks.append(.line(line))
            }
        }
        if !tableBuffer.isEmpty {
            blocks.append(.table(tableBuffer))
        }
        return blocks
    }

    /// Build styled text from segments (used for table rows).
    private func buildStyledText(from segments: [StyledSegment]) -> Text {
        var result = Text("")
        for segment in segments {
            let fgColor = ANSIColorMapper.color(for: segment.style.fgColor)
            var text = Text(segment.text)
                .foregroundColor(segment.style.isDim ? fgColor.opacity(0.6) : fgColor)
            if segment.style.isBold { text = text.bold() }
            if segment.style.isItalic { text = text.italic() }
            if segment.style.isUnderline { text = text.underline() }
            result = result + text
        }
        return result
    }
}

// MARK: - Terminal Line View

/// Renders a single terminal line with a marker column (›/·) and indented content.
struct TerminalLineView: View {
    let line: TerminalLine

    var body: some View {
        if line.segments.isEmpty {
            Text(" ")
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 18)
        } else {
            let parsed = parseLine()

            HStack(alignment: .top, spacing: 4) {
                // Marker column — fixed-width, invisible for continuation lines.
                Text(parsed.marker.character)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                    .opacity(parsed.marker == .none ? 0 : 1)

                // Content — text flows next to marker.
                // User messages use adaptive color so text is readable in light mode.
                buildAttributedText(
                    from: parsed.content,
                    adaptiveColor: parsed.marker == .user
                )
                .font(.system(size: 13, design: .monospaced))
            }
            .background {
                if parsed.marker == .user {
                    // Extend background beyond text without shifting content.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .padding(.horizontal, -6)
                        .padding(.vertical, -6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Marker Parsing

    private enum LineMarker: Equatable {
        case user, assistant, none

        var character: String {
            switch self {
            case .user: return "\u{203A}"      // ›
            case .assistant: return "\u{00B7}"  // ·
            case .none: return " "
            }
        }
    }

    /// Extract the conversation marker and remaining content segments.
    private func parseLine() -> (marker: LineMarker, content: [StyledSegment]) {
        guard !line.segments.isEmpty,
              let firstScalar = line.segments[0].text.unicodeScalars.first else {
            return (.none, line.segments)
        }

        let marker: LineMarker
        if firstScalar == "\u{203A}" { marker = .user }
        else if firstScalar == "\u{00B7}" { marker = .assistant }
        else { return (.none, line.segments) }

        // Strip marker character (and optional space after it) from segments.
        var segments = line.segments
        var remaining = String(segments[0].text.dropFirst())
        if remaining.hasPrefix(" ") { remaining = String(remaining.dropFirst()) }

        if remaining.isEmpty {
            segments.removeFirst()
            // Strip leading space from next segment if present.
            if !segments.isEmpty, segments[0].text.hasPrefix(" ") {
                let stripped = String(segments[0].text.dropFirst())
                if stripped.isEmpty { segments.removeFirst() }
                else { segments[0] = StyledSegment(text: stripped, style: segments[0].style) }
            }
        } else {
            segments[0] = StyledSegment(text: remaining, style: segments[0].style)
        }

        return (marker, segments)
    }

    // MARK: - Text Building

    private func buildAttributedText(from segments: [StyledSegment], adaptiveColor: Bool = false) -> Text {
        var result = Text("")
        for segment in segments {
            // Adaptive: use .primary so text is readable in both light/dark mode.
            let fgColor = adaptiveColor ? Color.primary : ANSIColorMapper.color(for: segment.style.fgColor)
            var text = Text(segment.text)
                .foregroundColor(segment.style.isDim ? fgColor.opacity(0.6) : fgColor)
            if segment.style.isBold { text = text.bold() }
            if segment.style.isItalic { text = text.italic() }
            if segment.style.isUnderline { text = text.underline() }
            result = result + text
        }
        return result
    }
}
