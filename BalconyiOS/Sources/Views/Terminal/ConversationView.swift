import SwiftUI
import BalconyShared

/// Renders parsed terminal conversation lines with a native input bar.
/// Keystrokes are streamed live to the Mac terminal as the user types.
struct ConversationView: View {
    let lines: [TerminalLine]
    let slashCommands: [SlashCommandInfo]
    let projectFiles: [String]
    let activePrompt: InteractivePrompt?
    let pendingInputText: String
    var onSendInput: ((String) -> Void)?

    @State private var inputText = ""
    @State private var previousText = ""
    /// Timestamp of the last local keystroke. While the user is actively typing
    /// on iOS we suppress incoming `pendingInputText` sync to avoid the Mac's
    /// echo overwriting the local input mid-edit.
    @State private var lastLocalKeystroke: Date = .distantPast
    @State private var isNearBottom = true
    @State private var showEmptyState = false
    @State private var showSlashMenu = false
    @State private var showFilePicker = false
    @State private var showBashMode = false
    @State private var showBackgroundMode = false
    @State private var promptJustAnswered = false
    @FocusState private var inputFocused: Bool

    /// Whether the input starts with "!" (bash mode prefix).
    private var isBashMode: Bool { inputText.hasPrefix("!") }

    /// Whether the input starts with "&" (background mode prefix).
    private var isBackgroundMode: Bool { inputText.hasPrefix("&") }

    /// Find the last "/" in the input and return the text after it as the filter query.
    /// Returns nil if no "/" is present (meaning the menu should be hidden).
    private var slashQuery: String? {
        guard let slashIndex = inputText.lastIndex(of: "/") else { return nil }
        let afterSlash = inputText[inputText.index(after: slashIndex)...]
        // Only treat it as a command query if there's no space after the slash yet
        // (once a space appears, the user is done picking a command).
        if afterSlash.contains(" ") { return nil }
        return String(afterSlash)
    }

    /// Find the last "@" in the input and return the text after it as the file filter query.
    /// Returns nil if no "@" is present (meaning the file picker should be hidden).
    private var atQuery: String? {
        guard let atIndex = inputText.lastIndex(of: "@") else { return nil }
        let afterAt = inputText[inputText.index(after: atIndex)...]
        if afterAt.contains(" ") { return nil }
        return String(afterAt)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if lines.isEmpty && showEmptyState {
                ConversationEmptyView()
                    .transition(.opacity.animation(.easeIn(duration: 0.5)))
            }

            // Conversation scroll area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedBlocks, id: \.id) { block in
                            switch block {
                            case .spacer:
                                Color.clear
                                    .frame(height: 18)
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

                        // Invisible anchor to detect proximity to bottom
                        Color.clear
                            .frame(height: 1)
                            .id("bottom-anchor")
                            .onAppear { isNearBottom = true }
                            .onDisappear { isNearBottom = false }
                    }
                    .padding(.top, 8)
                    // Bottom padding so content scrolls above the input bar + fade
                    .padding(.bottom, 100)
                }
                .contentShape(Rectangle())
                .onTapGesture { handleOutsideTap() }
                .onChange(of: lines.count) { _ in
                    if isNearBottom {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .overlay(alignment: .bottom) {
                    if !isNearBottom {
                        Button {
                            BalconyTheme.hapticLight()
                            scrollToBottom(proxy: proxy, animated: true)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(BalconyTheme.textPrimary)
                                .frame(width: 36, height: 36)
                        }
                        .modifier(LiquidGlassCapsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                        .padding(.bottom, 80)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isNearBottom)
                    }
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

                // Interactive prompt overlay — takes priority over slash/file menus
                if let prompt = activePrompt, !promptJustAnswered {
                    PromptOverlayView(prompt: prompt) { input in
                        promptJustAnswered = true
                        onSendInput?(input)
                    }
                    .padding(.bottom, BalconyTheme.spacingSM)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showFilePicker, !projectFiles.isEmpty {
                    // File picker menu — floats above the input bar
                    FilePickerMenu(
                        files: projectFiles,
                        query: atQuery ?? ""
                    ) { file in
                        selectFile(file)
                    }
                    .padding(.horizontal, BalconyTheme.spacingSM)
                    .padding(.bottom, BalconyTheme.spacingMD)
                    .transition(.menuPanel)
                } else if showSlashMenu, !slashCommands.isEmpty {
                    // Slash command menu — floats above the input bar
                    SlashCommandMenu(
                        commands: slashCommands,
                        query: slashQuery ?? ""
                    ) { command in
                        selectSlashCommand(command)
                    }
                    .padding(.horizontal, BalconyTheme.spacingSM)
                    .padding(.bottom, BalconyTheme.spacingMD)
                    .transition(.menuPanel)
                }

                // Mode badge — appears above input bar when ! or & is typed
                if showBashMode || showBackgroundMode {
                    HStack(spacing: 6) {
                        Image(systemName: showBashMode ? "terminal" : "moon.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(showBashMode ? "Bash Mode" : "Background Mode")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(showBashMode ? BalconyTheme.accent : BalconyTheme.textSecondary.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(
                            showBashMode
                                ? BalconyTheme.accent.opacity(0.12)
                                : BalconyTheme.textSecondary.opacity(0.12)
                        )
                    )
                    .padding(.bottom, 10)
                    .transition(.offset(y: 10).combined(with: .opacity))
                }

                // Input bar — glass pill
                HStack(spacing: BalconyTheme.spacingSM) {
                    // Slash command button — inserts "/" to trigger the menu
                    Button {
                        BalconyTheme.hapticLight()
                        inputText += "/"
                    } label: {
                        Text("/")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(showSlashMenu ? BalconyTheme.accent : BalconyTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }

                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(.plain)
                        .font(BalconyTheme.monoFont(15))
                        .focused($inputFocused)
                        .onSubmit { submitInput() }
                        .onChange(of: inputText) { newValue in
                            sendLiveKeystrokes(from: previousText, to: newValue)
                            previousText = newValue
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showSlashMenu = slashQuery != nil && atQuery == nil
                                showFilePicker = atQuery != nil
                                showBashMode = isBashMode
                                showBackgroundMode = isBackgroundMode
                            }
                        }
                        .padding(.vertical, 12)

                    Button(action: submitInput) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(inputText.isEmpty ? BalconyTheme.textSecondary : BalconyTheme.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(inputText.isEmpty)
                }
                .modifier(LiquidGlassCapsule())
                .overlay {
                    // Animated orange glow with shimmer when in bash mode (! prefix)
                    if showBashMode {
                        BashModeGlow()
                            .transition(.opacity)
                    }
                }
                .opacity(showBackgroundMode ? 0.7 : 1.0)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.horizontal, BalconyTheme.spacingLG)
                .padding(.bottom, BalconyTheme.spacingSM)
            }
        }
        .background {
            BalconyTheme.background.ignoresSafeArea()
        }
        .task(id: lines.isEmpty) {
            showEmptyState = false
            guard lines.isEmpty else { return }
            // Brief delay so the empty state doesn't flash during initial load
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            showEmptyState = true
        }
        .onChange(of: activePrompt) { _ in
            // Reset the guard when the prompt changes (new prompt or cleared).
            promptJustAnswered = false
        }
        .onChange(of: pendingInputText) { newValue in
            // Sync Mac's terminal input → iOS input field.
            // Skip if the iOS user typed recently — those updates are just echoes
            // of keystrokes we already sent. Once typing pauses (>0.5s), resume
            // syncing so Mac-originated edits come through.
            guard newValue != inputText else { return }
            let elapsed = Date().timeIntervalSince(lastLocalKeystroke)
            guard elapsed > 0.5 else { return }
            previousText = newValue
            inputText = newValue
        }
    }

    // MARK: - Scrolling

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard !lines.isEmpty else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }

    // MARK: - Live Input

    /// Send the diff between old and new text as live keystrokes.
    private func sendLiveKeystrokes(from oldText: String, to newText: String) {
        guard oldText != newText else { return }
        lastLocalKeystroke = Date()

        if newText.hasPrefix(oldText) && newText.count > oldText.count {
            // Characters added at end — send just the new ones.
            let added = String(newText.dropFirst(oldText.count))
            onSendInput?(added)
        } else if oldText.hasPrefix(newText) && newText.count < oldText.count {
            // Characters deleted from end — send DEL (backspace).
            let deleteCount = oldText.count - newText.count
            onSendInput?(String(repeating: "\u{7f}", count: deleteCount))
        } else {
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
        BalconyTheme.hapticLight()
        onSendInput?("\r")
        // Set previousText first so onChange doesn't send backspaces for the clear.
        previousText = ""
        inputText = ""
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            showSlashMenu = false
            showFilePicker = false
            showBashMode = false
            showBackgroundMode = false
        }
    }

    /// Handle tapping outside the input bar / menus.
    /// If a menu is open, close it first. Otherwise dismiss the keyboard.
    private func handleOutsideTap() {
        if showFilePicker || showSlashMenu {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                showFilePicker = false
                showSlashMenu = false
            }
        } else {
            inputFocused = false
        }
    }

    /// Select a command from the slash menu: replace the "/partial" with "/command ".
    private func selectSlashCommand(_ command: SlashCommandInfo) {
        guard let slashIndex = inputText.lastIndex(of: "/") else { return }

        // Erase everything from the "/" onward in the terminal
        let suffixToErase = inputText[slashIndex...]
        onSendInput?(String(repeating: "\u{7f}", count: suffixToErase.count))

        // Send the full command name + trailing space
        let replacement = command.displayName + " "
        onSendInput?(replacement)

        // Update local text: keep everything before "/" and append the command + space
        let prefix = String(inputText[..<slashIndex])
        let newText = prefix + replacement
        previousText = newText
        inputText = newText

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            showSlashMenu = false
        }
    }

    /// Select a file from the picker: replace "@partial" with "@filepath".
    private func selectFile(_ file: String) {
        guard let atIndex = inputText.lastIndex(of: "@") else { return }

        // Erase everything after the "@" in the terminal (keep the @ itself)
        let afterAt = inputText[inputText.index(after: atIndex)...]
        if !afterAt.isEmpty {
            onSendInput?(String(repeating: "\u{7f}", count: afterAt.count))
        }

        // Send the full file path (@ is already in the terminal)
        onSendInput?(file + " ")

        // Update local text: keep everything up to and including "@", append file path + space
        let prefix = String(inputText[...atIndex])
        let newText = prefix + file + " "
        previousText = newText
        inputText = newText

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            showFilePicker = false
        }
    }

    // MARK: - Table Grouping

    private enum ConversationBlock {
        case line(TerminalLine)
        case table([TerminalLine])
        /// Fixed-height gap inserted before each new message group.
        case spacer(Int)

        var id: Int {
            switch self {
            case .line(let l): return l.id
            case .table(let rows): return rows.first?.id ?? -1
            case .spacer(let anchorID): return -anchorID - 2
            }
        }
    }

    /// Check whether a line starts a new conversation message (set by the parser).
    private static func lineHasMarker(_ line: TerminalLine) -> Bool {
        line.markerRole != .none
    }

    /// Group consecutive table rows so they share a single horizontal scroll view.
    /// Inserts fixed-height spacers before message-start lines so that all items
    /// in the LazyVStack have predictable heights (prevents layout jumping).
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
                // Insert a spacer before lines that start a new message group.
                if Self.lineHasMarker(line) {
                    blocks.append(.spacer(line.id))
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
            .padding(.vertical, parsed.marker == .user ? 6 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(parsed: parsed))
        }
    }

    private func accessibilityText(parsed: (marker: LineMarker, content: [StyledSegment])) -> String {
        let text = parsed.content.map(\.text).joined()
        switch parsed.marker {
        case .user: return "You: \(text)"
        case .assistant: return "Claude: \(text)"
        case .none: return text
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
    /// Uses the parser-assigned `markerRole` (which checks the original ⏺/❯
    /// character AND its ANSI style) instead of raw character detection.
    /// This prevents spinner frames (✳, ⏺ with bright color) from being
    /// misidentified as message markers.
    private func parseLine() -> (marker: LineMarker, content: [StyledSegment]) {
        // Use the parser-assigned role — it already filtered out spinner chars.
        let marker: LineMarker
        switch line.markerRole {
        case .user:      marker = .user
        case .assistant: marker = .assistant
        case .none:      return (.none, line.segments)
        }

        guard !line.segments.isEmpty else { return (.none, line.segments) }

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

// MARK: - Menu Panel Transition

private struct MenuBlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    static var menuPanel: AnyTransition {
        .move(edge: .bottom)
        .combined(with: .opacity)
        .combined(with: .modifier(
            active: MenuBlurModifier(radius: 16),
            identity: MenuBlurModifier(radius: 0)
        ))
    }
}

// MARK: - Bash Mode Glow

/// Animated orange glow with a shimmer that sweeps around the capsule border.
private struct BashModeGlow: View {
    @State private var rotation: Double = 0

    var body: some View {
        let accent = BalconyTheme.accent

        Capsule()
            .strokeBorder(
                AngularGradient(
                    stops: [
                        .init(color: accent.opacity(0.15), location: 0.0),
                        .init(color: accent.opacity(0.15), location: 0.35),
                        .init(color: accent, location: 0.5),
                        .init(color: accent.opacity(0.15), location: 0.65),
                        .init(color: accent.opacity(0.15), location: 1.0),
                    ],
                    center: .center,
                    angle: .degrees(rotation)
                ),
                lineWidth: 2
            )
            .shadow(color: accent.opacity(0.4), radius: 6)
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Empty State

private struct ConversationEmptyView: View {
    var body: some View {
        VStack(spacing: BalconyTheme.spacingLG) {
            ZStack {
                Circle()
                    .fill(BalconyTheme.surfaceSecondary)
                    .frame(width: 64, height: 64)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(BalconyTheme.textSecondary)
            }

            VStack(spacing: BalconyTheme.spacingSM) {
                Text("No messages yet")
                    .font(BalconyTheme.headingFont(18))
                    .foregroundStyle(BalconyTheme.textPrimary)
                Text("Messages will appear as Claude responds.")
                    .font(BalconyTheme.bodyFont(14))
                    .foregroundStyle(BalconyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -60)
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
        ], isWrapped: false, markerRole: .user),
        TerminalLine(id: 1, segments: [], isWrapped: false),
        TerminalLine(id: 2, segments: [
            StyledSegment(text: "\u{00B7} ", style: dim),
            StyledSegment(text: "I'll look into the login flow.", style: plain),
        ], isWrapped: false, markerRole: .assistant),
        TerminalLine(id: 3, segments: [
            StyledSegment(text: "  Let me check the auth module first.", style: plain),
        ], isWrapped: false),
        TerminalLine(id: 4, segments: [], isWrapped: false),
        TerminalLine(id: 5, segments: [
            StyledSegment(text: "\u{00B7} ", style: dim),
            StyledSegment(text: "Read", style: green),
            StyledSegment(text: " src/auth/login.ts", style: plain),
        ], isWrapped: false, markerRole: .assistant),
        TerminalLine(id: 6, segments: [], isWrapped: false),
        TerminalLine(id: 7, segments: [
            StyledSegment(text: "\u{00B7} ", style: dim),
            StyledSegment(text: "Found the issue — the token refresh", style: plain),
        ], isWrapped: false, markerRole: .assistant),
        TerminalLine(id: 8, segments: [
            StyledSegment(text: "  is using an expired secret key.", style: plain),
        ], isWrapped: false),
    ]

    ConversationView(
        lines: sampleLines,
        slashCommands: [
            .init(name: "help", description: "Get help with Claude Code", source: .builtIn),
            .init(name: "compact", description: "Compact conversation with summary", source: .builtIn),
            .init(name: "debug", description: "Investigate and diagnose issues", source: .global, argumentHint: "[error or file]"),
            .init(name: "test", description: "Run tests with analysis", source: .project),
        ],
        projectFiles: ["src/auth/login.ts", "src/components/Button.tsx", "package.json"],
        activePrompt: nil,
        pendingInputText: ""
    )
    .background(BalconyTheme.background)
}
#endif
