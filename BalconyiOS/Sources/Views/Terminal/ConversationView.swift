import SwiftUI
import BalconyShared

/// Renders parsed terminal conversation lines with a native input bar.
/// Keystrokes are streamed live to the Mac terminal as the user types.
struct ConversationView: View {
    let lines: [TerminalLine]
    let slashCommands: [SlashCommandInfo]
    let projectFiles: [String]
    let activePrompt: InteractivePrompt?
    let pendingHookData: HookEventPayload?
    let pendingIdlePrompt: IdlePromptPayload?
    let pendingInputText: String
    let availableSessions: [SessionInfo]
    let showSessionPicker: Bool
    let availableModels: [ModelInfo]
    let currentModelId: String?
    let showModelPicker: Bool
    let rewindTurns: [RewindTurnInfo]
    let showRewindPicker: Bool
    let pendingAskUserQuestion: AskUserQuestionPayload?
    var onSendInput: ((String) -> Void)?
    var onSubmitAskUserQuestion: (([String: String]) -> Void)?
    var onDismissAskUserQuestion: (() -> Void)?
    var onSelectSession: ((SessionInfo) -> Void)?
    var onRequestSessionPicker: (() -> Void)?
    var onDismissSessionPicker: (() -> Void)?
    var onSelectModel: ((ModelInfo) -> Void)?
    var onRequestModelPicker: (() -> Void)?
    var onDismissModelPicker: (() -> Void)?
    var onSelectRewind: ((RewindTurnInfo) -> Void)?
    var onRequestRewind: (() -> Void)?
    var onDismissRewindPicker: (() -> Void)?

    @State private var inputText = ""
    @State private var previousText = ""
    /// Timestamp of the last local keystroke. While the user is actively typing
    /// on iOS we suppress incoming `pendingInputText` sync to avoid the Mac's
    /// echo overwriting the local input mid-edit.
    @State private var lastLocalKeystroke: Date = .distantPast
    @State private var isNearBottom = true
    @State private var needsInitialScroll = true
    /// Track previous line count to only auto-scroll when content grows.
    @State private var lastLineCount = 0
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

    /// Whether the session picker is currently shown.
    private var isSessionPickerActive: Bool { showSessionPicker && !availableSessions.isEmpty }

    /// Whether the model picker is currently shown.
    private var isModelPickerActive: Bool { showModelPicker && !availableModels.isEmpty }

    /// Whether the rewind picker is currently shown.
    private var isRewindPickerActive: Bool { showRewindPicker && !rewindTurns.isEmpty }

    /// Placeholder text for the input field, adapting to active picker state.
    private var inputPlaceholder: String {
        if isSessionPickerActive { return "Type to search..." }
        if isModelPickerActive { return "Select a model..." }
        if isRewindPickerActive { return "Select a turn..." }
        return "Type a message..."
    }

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
                                    .padding(.vertical, line.markerRole == .user ? 6 : 0)
                                    .background(line.markerRole == .user ? BalconyTheme.surfaceSecondary : Color.clear)
                                    .overlay(alignment: .leading) {
                                        if line.markerRole == .user {
                                            Rectangle()
                                                .fill(BalconyTheme.accent)
                                                .frame(width: 3)
                                        }
                                    }
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

                        // Invisible anchor to detect proximity to bottom.
                        // onDisappear uses a brief delay so rapid content
                        // changes (spinner frames) don't cause isNearBottom
                        // to oscillate and break auto-scroll.
                        Color.clear
                            .frame(height: 1)
                            .id("bottom-anchor")
                            .onAppear {
                                isNearBottom = true
                                needsInitialScroll = false
                            }
                            .onDisappear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    guard !needsInitialScroll else { return }
                                    isNearBottom = false
                                }
                            }
                    }
                    .padding(.top, 8)
                    // Bottom padding so content scrolls above the input bar + fade
                    .padding(.bottom, 100)
                    // Suppress implicit animations to prevent layout jitter
                    // during rapid content updates (spinner, streaming).
                    .animation(nil, value: lines.count)
                }
                .contentShape(Rectangle())
                .onTapGesture { handleOutsideTap() }
                .onChange(of: lines.count) { newCount in
                    if needsInitialScroll {
                        scrollToBottom(proxy: proxy, animated: false)
                    } else if isNearBottom && newCount >= lastLineCount {
                        // Only auto-scroll when content grows (not on count
                        // oscillation from spinner/joining changes). Non-animated
                        // to prevent jitter during rapid streaming updates.
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    lastLineCount = newCount
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: inputFocused) { focused in
                    if focused {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
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

                // Session picker — takes priority over all other overlays
                if showSessionPicker, !availableSessions.isEmpty {
                    SessionPickerView(sessions: availableSessions, searchQuery: inputText, onSelect: { session in
                        onSelectSession?(session)
                    }, onDismiss: {
                        onDismissSessionPicker?()
                    })
                    .padding(.horizontal, BalconyTheme.spacingSM)
                    .padding(.bottom, BalconyTheme.spacingMD)
                    .transition(.menuPanel)
                }
                // Model picker — takes priority over prompts and menus
                else if showModelPicker, !availableModels.isEmpty {
                    ModelPickerView(
                        models: availableModels,
                        currentModelId: currentModelId,
                        onSelect: { model in onSelectModel?(model) },
                        onDismiss: { onDismissModelPicker?() }
                    )
                    .padding(.horizontal, BalconyTheme.spacingSM)
                    .padding(.bottom, BalconyTheme.spacingMD)
                    .transition(.menuPanel)
                }
                // Rewind picker — takes priority over prompts and menus
                else if showRewindPicker, !rewindTurns.isEmpty {
                    RewindPickerView(
                        turns: rewindTurns,
                        onSelect: { turn in onSelectRewind?(turn) },
                        onDismiss: { onDismissRewindPicker?() }
                    )
                    .padding(.horizontal, BalconyTheme.spacingSM)
                    .padding(.bottom, BalconyTheme.spacingMD)
                    .transition(.menuPanel)
                }
                // Structured AskUserQuestion card — takes priority over terminal-detected prompts
                else if let askQuestion = pendingAskUserQuestion {
                    AskUserQuestionCardView(
                        payload: askQuestion,
                        onComplete: { answers in onSubmitAskUserQuestion?(answers) },
                        onDismiss: { onDismissAskUserQuestion?() }
                    )
                    .padding(.horizontal, BalconyTheme.spacingSM)
                    .padding(.bottom, BalconyTheme.spacingMD)
                    .transition(.menuPanel)
                }
                // Interactive prompt overlay — takes priority over slash/file menus
                else if let prompt = activePrompt, !promptJustAnswered {
                    PromptOverlayView(prompt: prompt, hookData: pendingHookData) { input in
                        promptJustAnswered = true
                        onSendInput?(input)
                    }
                    .padding(.bottom, BalconyTheme.spacingSM)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                else if showFilePicker, !projectFiles.isEmpty {
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

                    TextField(inputPlaceholder, text: $inputText)
                        .textFieldStyle(.plain)
                        .font(BalconyTheme.monoFont(15))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($inputFocused)
                        .onSubmit { submitInput() }
                        .onChange(of: inputText) { newValue in
                            // When a picker is open, input is for local use only
                            if !isSessionPickerActive && !isModelPickerActive && !isRewindPickerActive {
                                sendLiveKeystrokes(from: previousText, to: newValue)
                            }
                            previousText = newValue
                            let pickerActive = isSessionPickerActive || isModelPickerActive || isRewindPickerActive
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showSlashMenu = slashQuery != nil && atQuery == nil && !pickerActive
                                showFilePicker = atQuery != nil && !pickerActive
                                showBashMode = isBashMode && !pickerActive
                                showBackgroundMode = isBackgroundMode && !pickerActive
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
        .onChange(of: showSessionPicker) { isShowing in
            // Clear input when the picker opens or closes so search starts fresh
            // and the field is clean when returning to normal mode.
            previousText = ""
            inputText = ""
        }
        .onChange(of: showModelPicker) { _ in
            // Clear input when the model picker opens or closes.
            previousText = ""
            inputText = ""
        }
        .onChange(of: showRewindPicker) { _ in
            // Clear input when the rewind picker opens or closes.
            previousText = ""
            inputText = ""
        }
        .onChange(of: pendingInputText) { newValue in
            // Don't sync Mac's terminal input while a picker is active
            guard !isSessionPickerActive && !isModelPickerActive && !isRewindPickerActive else { return }
            // Sync Mac's terminal input → iOS input field.
            // Skip if the iOS user typed recently — those updates are just echoes
            // of keystrokes we already sent. Once typing pauses (>0.5s), resume
            // syncing so Mac-originated edits come through.
            guard newValue != inputText else { return }
            let elapsed = Date().timeIntervalSince(lastLocalKeystroke)
            guard elapsed > 0.5 else { return }
            // Don't truncate: if Mac's text is a prefix of what we have, the Mac
            // parser likely only read the first terminal row of a wrapped input.
            // Overwriting would desync previousText and cause corrupt diffs.
            guard !inputText.hasPrefix(newValue) || newValue.count >= inputText.count else { return }
            previousText = newValue
            inputText = newValue
        }
    }

    // MARK: - Scrolling

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard !lines.isEmpty else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom-anchor", anchor: .top)
            }
        } else {
            proxy.scrollTo("bottom-anchor", anchor: .top)
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
            // Combine into a single send so the backspaces and replacement text
            // travel in one WebSocket message, avoiding a race where two separate
            // Task-per-send calls can arrive out of order and corrupt the terminal.
            var combined = ""
            if !oldText.isEmpty {
                combined += String(repeating: "\u{7f}", count: oldText.count)
            }
            if !newText.isEmpty {
                combined += newText
            }
            if !combined.isEmpty {
                onSendInput?(combined)
            }
        }
    }

    /// Submit the current input (send carriage return and clear).
    private func submitInput() {
        // When a picker is open, Enter is a no-op (input is for search only)
        guard !isSessionPickerActive && !isModelPickerActive && !isRewindPickerActive else { return }
        guard !inputText.isEmpty else { return }
        BalconyTheme.hapticLight()

        // Intercept /resume: show native picker instead of sending to terminal.
        // We clear the terminal input (send backspaces) rather than sending Enter,
        // so Claude Code never processes /resume and never shows its own terminal picker.
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        if trimmed == "/resume" || trimmed.hasPrefix("/resume ") {
            // Clear /resume from the Mac's terminal input (send backspaces for each char)
            onSendInput?(String(repeating: "\u{7f}", count: inputText.count))
            // Request native session picker from Mac
            onRequestSessionPicker?()
        } else if trimmed == "/model" || trimmed.hasPrefix("/model ") {
            // Clear /model from the Mac's terminal input
            onSendInput?(String(repeating: "\u{7f}", count: inputText.count))
            // Request native model picker from Mac
            onRequestModelPicker?()
        } else if trimmed == "/rewind" || trimmed.hasPrefix("/rewind ") {
            // Clear /rewind from the Mac's terminal input
            onSendInput?(String(repeating: "\u{7f}", count: inputText.count))
            // Show native rewind picker (computed locally, no Mac round-trip)
            onRequestRewind?()
        } else {
            onSendInput?("\r")
        }

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
        line.markerRole == .user || line.markerRole == .assistant
    }

    /// Lines to display, with AskUserQuestion TUI stripped when the native card is showing.
    private var displayLines: [TerminalLine] {
        guard pendingAskUserQuestion != nil else { return lines }
        return Self.stripAskUserQuestionTUI(from: lines)
    }

    /// Strip the AskUserQuestion TUI chrome from terminal lines.
    /// Detects the block by scanning for the navigation hint line at the bottom
    /// (`Enter to select` / `Tab/Arrow keys`) and the tab header at the top.
    private static func stripAskUserQuestionTUI(from lines: [TerminalLine]) -> [TerminalLine] {
        // Find the navigation hint line near the bottom (distinctive AskUserQuestion TUI marker)
        let searchRange = max(0, lines.count - 40)..<lines.count
        var hintLineIdx: Int?
        for i in searchRange.reversed() {
            let text = lines[i].segments.map(\.text).joined()
            if text.contains("Enter to select") || text.contains("Tab/Arrow keys") || text.contains("Esc to cancel") {
                hintLineIdx = i
                break
            }
        }

        guard let bottomIdx = hintLineIdx else { return lines }

        // Scan backward to find the start of the TUI block.
        // Look for the tab header line (contains □ or ← or Submit →) or a horizontal rule (─).
        var topIdx = bottomIdx
        for i in stride(from: bottomIdx - 1, through: max(0, bottomIdx - 30), by: -1) {
            let text = lines[i].segments.map(\.text).joined()
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            // The tab header line or a horizontal rule above the TUI
            if trimmed.contains("□") || trimmed.contains("←") || trimmed.contains("Submit") {
                topIdx = i
                // Check if there's a horizontal rule line just above
                if i > 0 {
                    let above = lines[i - 1].segments.map(\.text).joined().trimmingCharacters(in: .whitespaces)
                    if above.allSatisfy({ $0 == "─" || $0 == " " || $0 == "_" }) && !above.isEmpty {
                        topIdx = i - 1
                    }
                }
                break
            }
            topIdx = i
        }

        // Strip from topIdx through the end (includes trailing empty lines)
        var result = Array(lines.prefix(topIdx))
        // Trim trailing empty lines
        while let last = result.last,
              last.segments.isEmpty || last.segments.allSatisfy({ $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
            result.removeLast()
            if result.isEmpty { break }
        }
        return result
    }

    /// Group consecutive table rows so they share a single horizontal scroll view.
    /// Inserts fixed-height spacers before message-start lines so that all items
    /// in the LazyVStack have predictable heights (prevents layout jumping).
    private var groupedBlocks: [ConversationBlock] {
        var blocks: [ConversationBlock] = []
        var tableBuffer: [TerminalLine] = []

        for line in displayLines {
            if line.isTableRow {
                tableBuffer.append(line)
            } else {
                if !tableBuffer.isEmpty {
                    blocks.append(.table(tableBuffer))
                    tableBuffer = []
                }
                // Insert a spacer before lines that start a new message group.
                // Absorb any preceding empty lines so the gap is always exactly
                // one spacer (18pt), regardless of how many empty terminal lines
                // Claude Code inserts — their count changes as the buffer grows.
                let needsSpacer = Self.lineHasMarker(line) || line.markerRole == .spinner
                if needsSpacer {
                    while case .line(let prev) = blocks.last,
                          Self.isEmptyLine(prev) {
                        blocks.removeLast()
                    }
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

    /// Check whether a terminal line is empty/whitespace-only.
    private static func isEmptyLine(_ line: TerminalLine) -> Bool {
        line.segments.isEmpty ||
        line.segments.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
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
            if segment.style.isStrikethrough { text = text.strikethrough() }
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

            ZStack(alignment: .topLeading) {
                // Marker — overlaid at leading edge with fixed frame.
                // Fixed 14×18 prevents glyph metric differences between
                // spinner characters (✶ ✻ ✢ · ✽) from changing the
                // ZStack dimensions and causing ScrollView adjustment.
                Text(parsed.marker.character)
                    .font(BalconyTheme.monoFont())
                    .foregroundColor(markerColor(parsed.marker))
                    .opacity(parsed.marker == .none ? 0 : 1)
                    .frame(width: 14, height: 18, alignment: .leading)

                // Content — always starts at fixed 18pt offset (14 marker + 4 gap).
                buildAttributedText(
                    from: parsed.content,
                    adaptiveColor: parsed.marker == .user
                )
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 18, alignment: .topLeading)
                .padding(.leading, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(parsed: parsed))
        }
    }

    /// Color for the marker column character.
    private func markerColor(_ marker: LineMarker) -> Color {
        switch marker {
        case .user: return BalconyTheme.accent
        case .assistant: return BalconyTheme.textSecondary
        case .none: return .clear
        case .spinner:
            // Use the ANSI color from the original first segment if available.
            if let style = line.segments.first?.style {
                return ANSIColorMapper.color(for: style.fgColor)
            }
            return BalconyTheme.textSecondary
        }
    }

    private func accessibilityText(parsed: (marker: LineMarker, content: [StyledSegment])) -> String {
        let text = parsed.content.map(\.text).joined()
        switch parsed.marker {
        case .user: return "You: \(text)"
        case .assistant: return "Claude: \(text)"
        case .none, .spinner: return text
        }
    }

    // MARK: - Marker Parsing

    private enum LineMarker: Equatable {
        case user, assistant, none
        /// A non-marker leading symbol (e.g. spinner ✳) extracted into the
        /// fixed-width column so text alignment stays stable across frames.
        case spinner(String)

        var character: String {
            switch self {
            case .user: return "\u{203A}"      // ›
            case .assistant: return "\u{00B7}"  // ·
            case .none: return " "
            case .spinner(let ch): return ch
            }
        }

        var isMessageStart: Bool {
            self == .user || self == .assistant
        }
    }

    /// Extract the conversation marker and remaining content segments.
    /// Uses the parser-assigned `markerRole` (which checks the original ⏺/❯
    /// character AND its ANSI style) instead of raw character detection.
    /// This prevents spinner frames (✳, ⏺ with bright color) from being
    /// misidentified as message markers.
    ///
    /// Non-marker lines that start with a single non-ASCII symbol followed
    /// by a space (spinner/progress lines) get that symbol extracted into
    /// the marker column so text alignment is stable across spinner frames.
    private func parseLine() -> (marker: LineMarker, content: [StyledSegment]) {
        let marker: LineMarker
        switch line.markerRole {
        case .user:      marker = .user
        case .assistant: marker = .assistant
        case .spinner:
            // Parser detected a spinner line by its color. Extract the
            // leading symbol into the marker column for stable alignment.
            guard !line.segments.isEmpty,
                  let ch = line.segments.first?.text.first else {
                return (.none, line.segments)
            }
            return (.spinner(String(ch)), stripLeadingChar(from: line.segments))
        case .none:
            // Fallback: check for spinner-like leading character.
            return extractSpinner()
        }

        guard !line.segments.isEmpty else { return (.none, line.segments) }

        // Strip marker character (and optional space after it) from segments.
        return (marker, stripLeadingChar(from: line.segments))
    }

    /// If the line starts with a non-ASCII symbol (spinner/bullet), extract it
    /// into the fixed-width marker column. Scans across segment boundaries and
    /// strips all surrounding whitespace so the content position is stable
    /// regardless of character width or ANSI styling differences.
    private func extractSpinner() -> (marker: LineMarker, content: [StyledSegment]) {
        // Scan all segments for the first non-whitespace character.
        var spinnerChar: Character?
        var foundSegIdx = 0
        var foundCharOffset = 0

        for (segIdx, seg) in line.segments.enumerated() {
            var offset = 0
            for ch in seg.text {
                if ch != " " && ch != "\0" {
                    spinnerChar = ch
                    foundSegIdx = segIdx
                    foundCharOffset = offset
                    break
                }
                offset += 1
            }
            if spinnerChar != nil { break }
        }

        guard let ch = spinnerChar,
              let scalar = ch.unicodeScalars.first,
              scalar.value > 0x7F,
              !ch.isLetter else {
            return (.none, line.segments)
        }

        // Build content: drop everything up to and including the spinner char,
        // then strip all leading whitespace (space after char + width padding).
        var content = Array(line.segments[foundSegIdx...])
        let afterChar = String(content[0].text.dropFirst(foundCharOffset + 1))
        if afterChar.isEmpty {
            content.removeFirst()
        } else {
            content[0] = StyledSegment(text: afterChar, style: content[0].style)
        }

        // Strip leading spaces across segment boundaries.
        while !content.isEmpty {
            let stripped = content[0].text.drop(while: { $0 == " " || $0 == "\0" })
            if stripped.isEmpty {
                content.removeFirst()
            } else {
                content[0] = StyledSegment(text: String(stripped), style: content[0].style)
                break
            }
        }

        return (.spinner(String(ch)), content)
    }

    /// Strip the first character and all leading spaces from segments.
    /// Strips across segment boundaries to handle ambiguous-width characters
    /// whose null padding cells become extra space segments.
    private func stripLeadingChar(from original: [StyledSegment]) -> [StyledSegment] {
        var segments = original
        var remaining = String(segments[0].text.dropFirst())
        // Strip all leading spaces (not just one) — handles width-mismatch padding.
        while remaining.hasPrefix(" ") { remaining = String(remaining.dropFirst()) }

        if remaining.isEmpty {
            segments.removeFirst()
            // Continue stripping leading spaces across subsequent segments.
            while !segments.isEmpty {
                let stripped = segments[0].text.drop(while: { $0 == " " })
                if stripped.isEmpty {
                    segments.removeFirst()
                } else {
                    segments[0] = StyledSegment(text: String(stripped), style: segments[0].style)
                    break
                }
            }
        } else {
            segments[0] = StyledSegment(text: remaining, style: segments[0].style)
        }
        return segments
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
            if segment.style.isStrikethrough { text = text.strikethrough() }
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
        pendingHookData: nil,
        pendingIdlePrompt: nil,
        pendingInputText: "",
        availableSessions: [],
        showSessionPicker: false,
        availableModels: [],
        currentModelId: nil,
        showModelPicker: false,
        rewindTurns: [],
        showRewindPicker: false,
        pendingAskUserQuestion: nil
    )
    .background(BalconyTheme.background)
}
#endif
