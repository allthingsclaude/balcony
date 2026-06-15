import SwiftUI
import UIKit
import BalconyShared

/// Renders parsed terminal conversation lines with a native input bar.
/// Keystrokes are streamed live to the Mac terminal as the user types.
struct ConversationView: View {
    /// Live PTY-parsed lines. Used only for the in-flight reply tail now that
    /// settled history is rendered from the structured `transcriptEvents`.
    let lines: [TerminalLine]
    /// Structured transcript (parsed from the session JSONL) — the reliable
    /// source for settled conversation history.
    let transcriptEvents: [TranscriptEvent]
    /// Just-sent messages shown immediately (dimmed) until they land in the JSONL.
    let optimisticMessages: [TranscriptEvent]
    /// True after the user interrupts the run (Esc) — suppresses the spinner.
    let interrupted: Bool
    /// True when the terminal reflects all input the phone has sent — gates
    /// adopting the Mac's input box so an in-flight echo can't clobber typing.
    let inputInSync: Bool
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
    /// Called with a plain message's text the moment it's submitted, for
    /// optimistic rendering (before the Mac round-trips it into the JSONL).
    var onMessageSubmitted: ((String) -> Void)?
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
    /// Pending "left the bottom" flip, cancelled if the bottom detector reappears.
    @State private var leftBottomWorkItem: DispatchWorkItem?
    @State private var showEmptyState = false
    @State private var showSlashMenu = false
    @State private var showFilePicker = false
    @State private var showBashMode = false
    @State private var showBackgroundMode = false
    @State private var promptJustAnswered = false

    /// Autocorrect/autocapitalization in the input field. Off by default —
    /// commands and file paths are the common case. Toggle lives in Settings.
    @AppStorage("input.autocorrect") private var autocorrectEnabled = false
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
        if isRewindPickerActive { return "Type to search..." }
        return "Type a message..."
    }

    /// Find the last "/" in the input and return the text after it as the filter query.
    /// Returns nil if no "/" is present (meaning the menu should be hidden).
    private var slashQuery: String? {
        menuQuery(trigger: "/")
    }

    /// Find the last "@" in the input and return the text after it as the file filter query.
    /// Returns nil if no "@" is present (meaning the file picker should be hidden).
    private var atQuery: String? {
        menuQuery(trigger: "@")
    }

    /// Shared trigger detection for the slash and @ menus. The trigger only
    /// counts at the start of a word — "path/to/file" or "user@host" must not
    /// open a menu — and the query ends at the first space.
    private func menuQuery(trigger: Character) -> String? {
        guard let triggerIndex = inputText.lastIndex(of: trigger) else { return nil }
        if triggerIndex > inputText.startIndex {
            let before = inputText[inputText.index(before: triggerIndex)]
            guard before == " " || before == "\n" else { return nil }
        }
        let after = inputText[inputText.index(after: triggerIndex)...]
        if after.contains(" ") { return nil }
        return String(after)
    }

    // MARK: - Transcript / Loader

    /// Settled history to render (sub-agent turns hidden, matching the TUI).
    private var visibleTranscript: [TranscriptEvent] {
        transcriptEvents.filter { !$0.isSidechain }
    }

    /// True when the assistant's reply is in flight — the last settled turn is
    /// the user's (a real message or a tool result Claude is still acting on),
    /// or we have an optimistic just-sent message pending.
    private var awaitingReply: Bool {
        transcriptEvents.last?.role == .user || !optimisticMessages.isEmpty
    }

    /// Show the working spinner only when Claude is actually generating — not
    /// while it's blocked on a prompt/question, idle waiting for input, or the
    /// user just interrupted the run (Esc).
    private var showLoader: Bool {
        awaitingReply && !interrupted
            && activePrompt == nil && pendingIdlePrompt == nil && pendingAskUserQuestion == nil
    }

    /// Structural item count (settled turns + optimistic + loader) for scroll/anim.
    private var displayCount: Int {
        visibleTranscript.count + optimisticMessages.count + (showLoader ? 1 : 0)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if transcriptEvents.isEmpty && !awaitingReply && showEmptyState {
                ConversationEmptyView()
                    .transition(.opacity.animation(.easeIn(duration: 0.5)))
            }

            // Conversation scroll area
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BalconyTheme.spacingMD) {
                        // Settled history — rendered natively from the structured
                        // JSONL transcript (no PTY screen-scrape guessing).
                        ForEach(visibleTranscript) { event in
                            TranscriptEventView(event: event)
                                .padding(.horizontal, 12)
                                .id(event.id)
                        }

                        // Optimistic just-sent messages — dimmed until the Mac
                        // echoes them back into the JSONL.
                        ForEach(optimisticMessages) { event in
                            TranscriptEventView(event: event)
                                .opacity(0.55)
                                .padding(.horizontal, 12)
                                .id(event.id)
                        }

                        // Working spinner while Claude generates the reply. The
                        // reply itself renders block-by-block from the JSONL as
                        // Claude writes it (thinking → text → tool cards).
                        if showLoader {
                            WorkingIndicator()
                                .padding(.horizontal, 12)
                                .id("loader")
                        }

                        // "Near bottom" detector — sits just above the input-bar
                        // spacer so it becomes visible when the last content
                        // line is visible above the input bar. Drives the
                        // auto-scroll-on-new-content logic.
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                // Cancel any pending "left the bottom" flip — the
                                // detector reappeared (e.g. right after an auto-
                                // scroll), so we're still at the bottom. Without
                                // this, a stale timer would set isNearBottom=false
                                // and silently stop following new messages.
                                leftBottomWorkItem?.cancel()
                                leftBottomWorkItem = nil
                                isNearBottom = true
                                needsInitialScroll = false
                            }
                            .onDisappear {
                                leftBottomWorkItem?.cancel()
                                let item = DispatchWorkItem {
                                    guard !needsInitialScroll else { return }
                                    isNearBottom = false
                                }
                                leftBottomWorkItem = item
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
                            }

                        // Spacer for the floating input bar + fade gradient —
                        // kept INSIDE the VStack so the scroll target below it
                        // is the true last element.
                        Color.clear.frame(height: 100)

                        // True bottom — scrollTo aligns this to viewport bottom
                        // for a complete scroll to end. With anchor: .bottom
                        // this lands on the max scroll offset no matter how
                        // content above it is still laying out.
                        Color.clear
                            .frame(height: 1)
                            .id("bottom-anchor")
                    }
                    .padding(.top, 8)
                    // Suppress implicit animations to prevent layout jitter
                    // during rapid content updates (spinner, streaming).
                    .animation(nil, value: displayCount)
                }
                // Native bottom anchoring. History replay arrives after the
                // view mounts, so proxy-based scrolling races LazyVStack
                // layout; these keep the view opened-at-bottom and pinned
                // while content streams in (only while already at the bottom —
                // reading scrolled-up history is never interrupted).
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .contentShape(Rectangle())
                .onTapGesture { handleOutsideTap() }
                // Drag the conversation down to dismiss the keyboard (tap
                // outside still works via handleOutsideTap above).
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: displayCount) { _ in
                    // Follow new content whenever we're at the bottom (or on the
                    // first load). Non-animated to avoid jitter during streaming.
                    if needsInitialScroll || isNearBottom {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: inputFocused) { focused in
                    if focused {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                // End of ScrollView. The scroll-to-bottom button lives as a
                // ZStack sibling (below) rather than an overlay on the
                // ScrollView — otherwise UIScrollView's pan gesture captures
                // taps during deceleration and the first tap only stops the
                // scroll instead of invoking the button.
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
                    .accessibilityLabel("Scroll to bottom")
                    .modifier(LiquidGlassCapsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.bottom, 80)
                    .transition(.scale.combined(with: .opacity))
                    .animation(BalconyTheme.springSnappy, value: isNearBottom)
                }
                } // end ZStack
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
                        searchQuery: inputText,
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
                    .transition(.menuPanel)
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
                    // (with a leading space if mid-word, so the trigger counts).
                    Button {
                        BalconyTheme.hapticLight()
                        // On an empty/whitespace field, start a fresh "/" at
                        // column 0 — a slash command must lead the input. Only
                        // prepend a separating space when there's real text before it.
                        if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            inputText = "/"
                        } else if inputText.hasSuffix(" ") || inputText.hasSuffix("\n") {
                            inputText += "/"
                        } else {
                            inputText += " /"
                        }
                    } label: {
                        Text("/")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(showSlashMenu ? BalconyTheme.accent : BalconyTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Slash commands")

                    TextField(inputPlaceholder, text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(BalconyTheme.monoFont(15))
                        .lineLimit(1...5)
                        .submitLabel(.return)
                        .autocorrectionDisabled(!autocorrectEnabled)
                        .textInputAutocapitalization(autocorrectEnabled ? .sentences : .never)
                        .focused($inputFocused)
                        .onSubmit { submitInput() }
                        .onChange(of: inputText) { newValue in
                            // When a picker is open, input is for local use only
                            if !isSessionPickerActive && !isModelPickerActive && !isRewindPickerActive {
                                sendLiveKeystrokes(from: previousText, to: newValue)
                            }
                            previousText = newValue
                            let pickerActive = isSessionPickerActive || isModelPickerActive || isRewindPickerActive
                            withAnimation(BalconyTheme.springSnappy) {
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
                    .accessibilityLabel("Send")
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
        .task(id: transcriptEvents.isEmpty) {
            showEmptyState = false
            guard transcriptEvents.isEmpty else { return }
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
            guard newValue != inputText else { return }
            // Ignore a whitespace-only box — Claude leaves a stray space in its
            // input after submitting, which would otherwise reappear in the field.
            if !newValue.isEmpty, newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
            // Adopt the Mac's box only once it reflects every keystroke we've
            // sent (seq-acked). Then a difference is a real CLI-side edit → show
            // it. Before that the box is stale/mid-update → don't clobber what
            // we're typing (submit's reconcile still guarantees the exact text).
            guard inputInSync else { return }
            // Brief settle delay so we don't adopt a box mid-redraw right after a keystroke.
            guard Date().timeIntervalSince(lastLocalKeystroke) > 0.3 else { return }
            previousText = newValue
            inputText = newValue
        }
        // Spring choreography for prompt surfaces. Presence-keyed so content
        // changes within an active prompt (e.g. selection moves) don't
        // re-trigger the entrance animation.
        .animation(BalconyTheme.springStandard, value: activePrompt == nil)
        .animation(BalconyTheme.springStandard, value: pendingAskUserQuestion == nil)
        // Prompt arrival is the app's attention moment — announce it.
        .onChange(of: activePrompt == nil) { isNil in
            if !isNil { BalconyTheme.hapticMedium() }
        }
        .onChange(of: pendingAskUserQuestion == nil) { isNil in
            if !isNil { BalconyTheme.hapticMedium() }
        }
    }

    // MARK: - Scrolling

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard !transcriptEvents.isEmpty || awaitingReply else { return }
        let go = {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
        go()
        // Retry once on the next runloop tick: LazyVStack only lays out rows
        // near the viewport, so the first scrollTo runs before rows further
        // down are measured. The second call catches the new content size
        // and lands on the true bottom.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { go() }
    }

    // MARK: - Live Input

    /// Send the diff between old and new text as live keystrokes.
    private func sendLiveKeystrokes(from oldText: String, to newText: String) {
        guard oldText != newText else { return }
        lastLocalKeystroke = Date()

        if newText.hasPrefix(oldText) && newText.count > oldText.count {
            // Characters added at end — send just the new ones.
            let added = String(newText.dropFirst(oldText.count))
            onSendInput?(bracketingPasteIfMultiline(added))
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
                onSendInput?(bracketingPasteIfMultiline(newText))
            }
        }
    }

    /// Multiline content (a paste, now that the field grows vertically) must
    /// reach the PTY as a bracketed paste — otherwise the terminal submits at
    /// every newline instead of preserving them in the input box.
    private func bracketingPasteIfMultiline(_ text: String) -> String {
        text.contains("\n") ? "\u{1b}[200~" + text + "\u{1b}[201~" : text
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
            // Optimistically render plain messages immediately (slash/bash/
            // background inputs render differently or not at all in the JSONL,
            // so they're excluded — they'd never get matched/removed).
            if !trimmed.hasPrefix("/"), !trimmed.hasPrefix("!"), !trimmed.hasPrefix("&") {
                onMessageSubmitted?(trimmed)
            }
            // Reconcile the Mac's input box to exactly what's on screen, then
            // submit. Live keystrokes mirror typing for feedback, but a dropped
            // one would otherwise send a truncated message — so we clear the box
            // (backspaces ≥ its contents) and re-send the full text atomically.
            let clear = String(repeating: "\u{7f}", count: inputText.count)
            onSendInput?(clear + bracketingPasteIfMultiline(inputText) + "\r")
        }

        // Set previousText first so onChange doesn't send backspaces for the clear.
        previousText = ""
        inputText = ""
        withAnimation(BalconyTheme.springSnappy) {
            showSlashMenu = false
            showFilePicker = false
            showBashMode = false
            showBackgroundMode = false
        }
    }

    // MARK: - Copy Helpers

    /// Plain text of a single line, marker chrome trimmed.
    private func plainText(of line: TerminalLine) -> String {
        line.segments.map(\.text).joined().trimmingCharacters(in: .whitespaces)
    }

    /// Full text of the message block containing `line`: from its marker line
    /// (❯/⏺) through the last continuation line before the next marker.
    private func messageText(containing line: TerminalLine) -> String {
        guard let idx = lines.firstIndex(where: { $0.id == line.id }) else {
            return plainText(of: line)
        }
        var start = idx
        while start > 0, lines[start].markerRole == .none { start -= 1 }
        var end = idx + 1
        while end < lines.count, lines[end].markerRole == .none { end += 1 }
        return lines[start..<end]
            .map { $0.segments.map(\.text).joined() }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Handle tapping outside the input bar / menus.
    /// If a menu is open, close it first. Otherwise dismiss the keyboard.
    private func handleOutsideTap() {
        if showFilePicker || showSlashMenu {
            withAnimation(BalconyTheme.springSnappy) {
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

        // Keep text before "/", append the command + space, and strip any leading
        // whitespace so the command sits at column 0 — otherwise " /clear" isn't
        // recognized as a command when submitted.
        let prefix = String(inputText[..<slashIndex])
        let newText = String((prefix + command.displayName + " ").drop(while: { $0 == " " || $0 == "\n" }))

        // Mirror to the Mac: clear the whole input box, then send the clean
        // command. Clearing everything (not just from "/") keeps the Mac's box
        // exactly equal to `inputText` so submit's reconcile stays in sync.
        onSendInput?(String(repeating: "\u{7f}", count: inputText.count) + newText)

        previousText = newText
        inputText = newText

        withAnimation(BalconyTheme.springSnappy) {
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

        withAnimation(BalconyTheme.springSnappy) {
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
    ///
    /// Called from the `lines`/AskUserQuestion change hooks and cached in
    /// `cachedBlocks` — never from `body` directly.
    private func computeGroupedBlocks() -> [ConversationBlock] {
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
                .foregroundColor(segment.style.isDim ? fgColor.opacity(0.7) : fgColor)
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
///
/// Equatable so SwiftUI can skip body re-evaluation for unchanged lines when
/// the conversation array is republished — only lines whose content actually
/// changed (typically the last few) pay the attributed-text rebuild cost.
struct TerminalLineView: View, Equatable {
    let line: TerminalLine

    var body: some View {
        if line.segments.isEmpty {
            Text(" ")
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 18)
        } else {
            let parsed = parseLine()
            let pinned = isStatusIndicator(parsed: parsed)

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
                // Status-indicator lines (spinners, tool-in-progress rows) have
                // dynamic text that changes second-to-second. If we let them
                // wrap, the wrap boundary toggles each frame and every row
                // below shifts vertically. Pin them to a single row.
                let content = buildAttributedText(
                    from: parsed.content,
                    adaptiveColor: parsed.marker == .user
                )
                .font(.system(size: 13, design: .monospaced))

                Group {
                    if pinned {
                        content
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(height: 18, alignment: .topLeading)
                    } else {
                        content
                            .frame(minHeight: 18, alignment: .topLeading)
                    }
                }
                .padding(.leading, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(parsed: parsed))
        }
    }

    /// True for "status indicator" rows whose content updates frame-by-frame
    /// (spinners, tool-in-progress lines). These are pinned to one visual row
    /// so text like `(42s · ↓ 177 tokens · thought for 14s)` growing past the
    /// wrap threshold can't push every following row up and down.
    ///
    /// Rules:
    /// - `.spinner` marker — always (✱ Spinning…, ✶ Thinking…)
    /// - Line starts with ⎿ (U+23BF) — tool-result continuation row
    /// - `.assistant` marker + content contains … (U+2026) — Claude's
    ///   in-progress tool status convention (● Reading 4 files…)
    private func isStatusIndicator(parsed: (marker: LineMarker, content: [StyledSegment])) -> Bool {
        if case .spinner = parsed.marker { return true }

        let text = parsed.content.map(\.text).joined()
        if text.first == "\u{23BF}" { return true }   // ⎿
        if parsed.marker == .assistant && text.contains("\u{2026}") { return true }
        return false
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
                .foregroundColor(segment.style.isDim ? fgColor.opacity(0.7) : fgColor)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                guard !reduceMotion else { return }
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
        transcriptEvents: [
            TranscriptEvent(id: "u1", role: .user, blocks: [.text("help me fix the login bug")]),
            TranscriptEvent(id: "a1", role: .assistant, blocks: [
                .text("I'll look into the login flow."),
                .toolUse(id: "t1", name: "Read", input: "src/auth/login.ts"),
            ]),
        ],
        optimisticMessages: [],
        interrupted: false,
        inputInSync: true,
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
