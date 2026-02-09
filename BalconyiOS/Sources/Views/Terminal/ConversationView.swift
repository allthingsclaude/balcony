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
        ZStack(alignment: .bottom) {
            // Conversation scroll area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedBlocks, id: \.id) { block in
                            switch block {
                            case .line(let line):
                                TerminalLineView(line: line)
                                    .padding(.horizontal, 12)
                                    .id(line.id)
                            case .table(let rows):
                                ScrollView(.horizontal, showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(rows) { row in
                                            buildStyledText(from: row.segments)
                                                .font(.system(size: 13, design: .monospaced))
                                        }
                                    }
                                    // Left padding aligns content with text after marker column.
                                    .padding(.leading, 24)
                                    .padding(.trailing, 20)
                                }
                                .overlay(codeBlockFadeOverlay)
                                .id(rows.first?.id ?? -1)
                            }
                        }
                    }
                    .padding(.top, 8)
                    // Bottom padding so content scrolls above the input bar + fade
                    .padding(.bottom, 64)
                }
                .onChange(of: lines.count) { _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }

            // Bottom fade + input bar — move together with keyboard
            VStack(spacing: 0) {
                Spacer()

                // Fade: content dissolves before the input bar
                LinearGradient(
                    stops: [
                        .init(color: BalconyTheme.background.opacity(0), location: 0),
                        .init(color: BalconyTheme.background.opacity(0.8), location: 0.5),
                        .init(color: BalconyTheme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 150)
                .offset(y: 100)
                .allowsHitTesting(false)

                // Input bar — glass pill
                HStack(spacing: BalconyTheme.spacingSM) {
                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(BalconyTheme.monoFont(15))
                        .focused($inputFocused)
                        .onSubmit { submitInput() }
                        .onChange(of: inputText) { newValue in
                            sendLiveKeystrokes(from: previousText, to: newValue)
                            previousText = newValue
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, BalconyTheme.spacingMD)

                    Button(action: submitInput) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(inputText.isEmpty ? BalconyTheme.textSecondary : BalconyTheme.accent)
                    }
                    .disabled(inputText.isEmpty)
                    .padding(.trailing, 6)
                }
                .modifier(LiquidGlassCapsule())
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.horizontal, BalconyTheme.spacingMD)
                .padding(.bottom, BalconyTheme.spacingSM)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background {
            BalconyTheme.background.ignoresSafeArea()
        }
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

    /// Gradient fade overlay for edge-to-edge scrollable code blocks.
    private var codeBlockFadeOverlay: some View {
        let bgColor = BalconyTheme.background
        return HStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: bgColor, location: 0),
                    .init(color: bgColor.opacity(0.6), location: 0.4),
                    .init(color: bgColor.opacity(0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 32)

            Spacer()

            LinearGradient(
                stops: [
                    .init(color: bgColor.opacity(0), location: 0),
                    .init(color: bgColor.opacity(0.6), location: 0.6),
                    .init(color: bgColor, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 32)
        }
        .allowsHitTesting(false)
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
                    .font(BalconyTheme.monoFont())
                    .foregroundColor(parsed.marker == .user ? BalconyTheme.accent : BalconyTheme.textSecondary)
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
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BalconyTheme.accent)
                            .frame(width: 3)
                        RoundedRectangle(cornerRadius: BalconyTheme.radiusSM)
                            .fill(BalconyTheme.surfaceSecondary)
                    }
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
        if firstScalar == Unicode.Scalar(0x203A) { marker = .user }
        else if firstScalar == Unicode.Scalar(0x00B7) { marker = .assistant }
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
            // Adaptive: use theme primary so text is readable in both light/dark mode.
            let fgColor = adaptiveColor ? BalconyTheme.textPrimary : ANSIColorMapper.color(for: segment.style.fgColor)
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

// MARK: - Liquid Glass Capsule

/// Applies iOS 26 Liquid Glass when available, falls back to material on older versions.
private struct LiquidGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}


// MARK: - Preview

#if DEBUG
#Preview {
    let plain = SegmentStyle()
    let bold = SegmentStyle(isBold: true)
    let green = SegmentStyle(fgColor: .palette(2), isBold: true)
    let dim = SegmentStyle(isDim: true)

    let sampleLines: [TerminalLine] = [
        TerminalLine(id: 0, segments: [
            StyledSegment(text: "\u{203A} ", style: bold),
            StyledSegment(text: "help me fix the login bug", style: plain),
        ], isWrapped: false),
        TerminalLine(id: 1, segments: [], isWrapped: false),
        TerminalLine(id: 2, segments: [
            StyledSegment(text: "\u{00B7} ", style: dim),
            StyledSegment(text: "I'll look into the login flow.", style: plain),
        ], isWrapped: false),
        TerminalLine(id: 3, segments: [
            StyledSegment(text: "  Let me check the auth module first.", style: plain),
        ], isWrapped: false),
        TerminalLine(id: 4, segments: [], isWrapped: false),
        TerminalLine(id: 5, segments: [
            StyledSegment(text: "\u{00B7} ", style: dim),
            StyledSegment(text: "Read", style: green),
            StyledSegment(text: " src/auth/login.ts", style: plain),
        ], isWrapped: false),
        TerminalLine(id: 6, segments: [], isWrapped: false),
        TerminalLine(id: 7, segments: [
            StyledSegment(text: "\u{00B7} ", style: dim),
            StyledSegment(text: "Found the issue — the token refresh", style: plain),
        ], isWrapped: false),
        TerminalLine(id: 8, segments: [
            StyledSegment(text: "  is using an expired secret key.", style: plain),
        ], isWrapped: false),
    ]

    ConversationView(lines: sampleLines)
        .background(BalconyTheme.background)
}
#endif
