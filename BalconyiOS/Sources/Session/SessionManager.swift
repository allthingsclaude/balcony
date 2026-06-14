import Foundation
import SwiftUI
import Observation
import UserNotifications
import BalconyShared
import Combine
import os

/// In-app banner for activity on a session the user isn't currently viewing.
struct AttentionToast: Equatable, Identifiable {
    let id = UUID()
    let sessionId: String
    let sessionName: String
    let message: String
    /// True for needs-a-decision (permission/question); false for finished/awaiting input.
    let isAttention: Bool
}

/// Manages Claude Code sessions received from the connected Mac.
///
/// `@Observable` gives per-property observation: views re-render only when a
/// property they actually read changes. This keeps high-frequency terminal
/// updates (`conversationLines`) from re-rendering the sidebar, session list,
/// and app shell on every PTY chunk.
@MainActor
@Observable
final class SessionManager {
    @ObservationIgnored
    private let logger = Logger(subsystem: "com.balcony.ios", category: "SessionManager")

    var sessions: [Session] = []
    var activeSession: Session?

    /// Parsed conversation lines from the headless terminal parser (PTY scrape).
    var conversationLines: [TerminalLine] = []

    /// Structured transcript events parsed from the session JSONL on the Mac.
    /// Rendered by `ConversationView` as settled history; the live PTY
    /// `conversationLines` supply only the in-flight reply tail.
    var transcriptEvents: [TranscriptEvent] = []

    /// Slash commands available for the active session.
    var slashCommands: [SlashCommandInfo] = []

    /// Project files for the active session (@ file picker).
    var projectFiles: [String] = []

    /// Detected interactive prompt (permission or multi-option) from terminal output.
    var activePrompt: InteractivePrompt?

    /// Structured hook data for the current permission prompt (from Mac hook listener).
    var pendingHookData: HookEventPayload?

    /// Idle prompt data (Claude waiting for user input, from Mac hook listener).
    var pendingIdlePrompt: IdlePromptPayload?

    /// Structured AskUserQuestion data (from Mac hook listener).
    var pendingAskUserQuestion: AskUserQuestionPayload?

    /// Session IDs that have a pending permission or question prompt (needs user action).
    var sessionsNeedingAttention: Set<String> = []

    /// Session IDs where AI is idle and waiting for the user's next prompt.
    var sessionsAwaitingInput: Set<String> = []

    /// Text currently in the Mac's input box (after ❯). Used to pre-fill the iOS input.
    var pendingInputText: String = ""

    /// Available sessions for native session picker (/resume command).
    var availableSessions: [SessionInfo] = []

    /// Show the native session picker UI.
    var showSessionPicker: Bool = false

    /// The PTY session ID that triggered the session picker (for routing selection back).
    @ObservationIgnored
    private var pickerPTYSessionId: String?

    /// Available models for native model picker (/model command).
    var availableModels: [ModelInfo] = []

    /// The currently active model ID (detected from session JSONL).
    var currentModelId: String?

    /// Show the native model picker UI.
    var showModelPicker: Bool = false

    /// The PTY session ID that triggered the model picker (for routing selection back).
    @ObservationIgnored
    private var modelPickerPTYSessionId: String?

    /// Computed rewind turns for native rewind picker (/rewind command).
    var rewindTurns: [RewindTurnInfo] = []

    /// Show the native rewind picker UI.
    var showRewindPicker: Bool = false

    /// In-app banner for activity on a non-active session while the app is open.
    var attentionToast: AttentionToast?

    /// Session IDs with notifications muted (persisted across launches).
    var mutedSessionIds: Set<String> = SessionManager.loadMutedSessionIds() {
        didSet { SessionManager.saveMutedSessionIds(mutedSessionIds) }
    }

    @ObservationIgnored
    private var parser: HeadlessTerminalParser?
    @ObservationIgnored
    private var parserCancellable: AnyCancellable?
    @ObservationIgnored
    private var promptCancellable: AnyCancellable?
    @ObservationIgnored
    private var pendingInputCancellable: AnyCancellable?

    @ObservationIgnored
    private weak var connectionManager: ConnectionManager?

    // MARK: - Muting

    /// Toggle notification muting for a session.
    func toggleMute(for sessionId: String) {
        if mutedSessionIds.contains(sessionId) {
            mutedSessionIds.remove(sessionId)
        } else {
            mutedSessionIds.insert(sessionId)
        }
    }

    private static let mutedSessionIdsKey = "mutedSessionIds"

    private static func loadMutedSessionIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: mutedSessionIdsKey) ?? [])
    }

    private static func saveMutedSessionIds(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: mutedSessionIdsKey)
    }

    // MARK: - Configuration

    /// Wire up the connection manager to send/receive session messages.
    func configure(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        connectionManager.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }
    }

    // MARK: - Session Actions

    /// Refresh the session list from the connected Mac.
    func refreshSessions() async {
        logger.info("Refreshing sessions")
        guard let connectionManager else {
            logger.warning("No connection manager configured")
            return
        }
        do {
            let msg = try BalconyMessage.create(type: .sessionList, payload: EmptyPayload())
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to request session list: \(error.localizedDescription)")
        }
    }

    /// Subscribe to real-time updates for a session.
    func subscribe(to session: Session) async {
        logger.info("Subscribing to session: \(session.id)")
        activeSession = session
        conversationLines = []
        transcriptEvents = []
        slashCommands = []
        projectFiles = []

        let cols = Int(session.cols ?? 80)
        let rows = Int(session.rows ?? 24)
        let newParser = HeadlessTerminalParser(cols: cols, rows: rows)
        self.parser = newParser
        parserCancellable = newParser.$conversationLines
            .receive(on: DispatchQueue.main)
            .assign(to: \.conversationLines, on: self)
        promptCancellable = newParser.$activePrompt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prompt in
                self?.activePrompt = prompt
                // Clear hook data when prompt disappears from terminal
                if prompt == nil {
                    self?.pendingHookData = nil
                }
            }
        pendingInputCancellable = newParser.$pendingInputText
            .receive(on: DispatchQueue.main)
            .assign(to: \.pendingInputText, on: self)

        guard let connectionManager else { return }
        do {
            let payload = SessionSubscribePayload(sessionId: session.id)
            let msg = try BalconyMessage.create(type: .sessionSubscribe, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to subscribe to session: \(error.localizedDescription)")
        }
    }

    /// Unsubscribe from a session.
    func unsubscribe(from session: Session) async {
        logger.info("Unsubscribing from session: \(session.id)")
        if activeSession?.id == session.id {
            activeSession = nil
            parserCancellable?.cancel()
            parserCancellable = nil
            promptCancellable?.cancel()
            promptCancellable = nil
            pendingInputCancellable?.cancel()
            pendingInputCancellable = nil
            parser = nil
            conversationLines = []
            activePrompt = nil
            pendingHookData = nil
            pendingIdlePrompt = nil
            pendingAskUserQuestion = nil
            pendingInputText = ""
            projectFiles = []
        }
        // Keep sidebar dot state — don't clear sets here, the session may still need attention

        guard let connectionManager else { return }
        do {
            let payload = SessionSubscribePayload(sessionId: session.id)
            let msg = try BalconyMessage.create(type: .sessionUnsubscribe, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to unsubscribe from session: \(error.localizedDescription)")
        }
    }

    /// Send user input to a session on the Mac.
    func sendInput(_ input: String, to session: Session) async {
        logger.info("Sending input to session: \(session.id)")
        // Clear idle prompt when user starts responding
        if input == "\r" && pendingIdlePrompt != nil {
            sessionsAwaitingInput.remove(session.id)
            pendingIdlePrompt = nil
        }
        guard let connectionManager else { return }
        do {
            let payload = UserInputPayload(sessionId: session.id, text: input)
            let msg = try BalconyMessage.create(type: .userInput, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to send input: \(error.localizedDescription)")
        }
    }

    /// Request the session picker from Mac (triggered when user submits /resume on iOS).
    func requestSessionPicker() async {
        guard let activeSession else {
            logger.warning("requestSessionPicker: no active session")
            return
        }
        guard let connectionManager else {
            logger.warning("requestSessionPicker: no connection manager")
            return
        }
        logger.info("Requesting session picker for PTY session: \(activeSession.id)")
        do {
            let payload = SessionPickerRequestPayload(ptySessionId: activeSession.id)
            let msg = try BalconyMessage.create(type: .sessionPickerRequest, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to request session picker: \(error.localizedDescription)")
        }
    }

    /// Dismiss the session picker without selecting.
    func dismissSessionPicker() {
        withAnimation(BalconyTheme.springSnappy) {
            showSessionPicker = false
        }
        availableSessions = []
        pickerPTYSessionId = nil
    }

    /// Send session picker selection back to Mac.
    func selectSession(_ session: SessionInfo) async {
        logger.info("Selecting session: \(session.id)")
        guard let connectionManager, let ptySessionId = pickerPTYSessionId else { return }
        do {
            let payload = SessionPickerSelectionPayload(sessionId: session.id, ptySessionId: ptySessionId)
            let msg = try BalconyMessage.create(type: .sessionPickerSelection, payload: payload)
            try await connectionManager.send(msg)
            withAnimation(BalconyTheme.springSnappy) {
                showSessionPicker = false
            }
        } catch {
            logger.error("Failed to send session selection: \(error.localizedDescription)")
        }
    }

    /// Request the model picker from Mac (triggered when user submits /model on iOS).
    func requestModelPicker() async {
        guard let activeSession else {
            logger.warning("requestModelPicker: no active session")
            return
        }
        guard let connectionManager else {
            logger.warning("requestModelPicker: no connection manager")
            return
        }
        logger.info("Requesting model picker for PTY session: \(activeSession.id)")
        do {
            let payload = ModelPickerRequestPayload(ptySessionId: activeSession.id)
            let msg = try BalconyMessage.create(type: .modelPickerRequest, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to request model picker: \(error.localizedDescription)")
        }
    }

    /// Dismiss the model picker without selecting.
    func dismissModelPicker() {
        withAnimation(BalconyTheme.springSnappy) {
            showModelPicker = false
        }
        availableModels = []
        currentModelId = nil
        modelPickerPTYSessionId = nil
    }

    /// Send model picker selection back to Mac.
    func selectModel(_ model: ModelInfo) async {
        logger.info("Selecting model: \(model.id)")
        guard let connectionManager, let ptySessionId = modelPickerPTYSessionId else { return }
        do {
            let payload = ModelPickerSelectionPayload(modelId: model.id, ptySessionId: ptySessionId)
            let msg = try BalconyMessage.create(type: .modelPickerSelection, payload: payload)
            try await connectionManager.send(msg)
            withAnimation(BalconyTheme.springSnappy) {
                showModelPicker = false
            }
        } catch {
            logger.error("Failed to send model selection: \(error.localizedDescription)")
        }
    }

    /// Show the rewind picker with turns computed locally from conversationLines.
    func showRewind() {
        rewindTurns = computeRewindTurns()
        guard !rewindTurns.isEmpty else {
            logger.info("No turns to rewind")
            return
        }
        withAnimation(BalconyTheme.springSnappy) {
            showRewindPicker = true
        }
    }

    /// Dismiss the rewind picker without selecting.
    func dismissRewindPicker() {
        withAnimation(BalconyTheme.springSnappy) {
            showRewindPicker = false
        }
        rewindTurns = []
    }

    /// Send rewind selection to Mac.
    func selectRewind(_ turn: RewindTurnInfo) async {
        logger.info("Selecting rewind: \(turn.id) turns")
        guard let connectionManager, let activeSession else { return }
        do {
            let payload = RewindSelectionPayload(turnCount: turn.id, ptySessionId: activeSession.id)
            let msg = try BalconyMessage.create(type: .rewindSelection, payload: payload)
            try await connectionManager.send(msg)
            withAnimation(BalconyTheme.springSnappy) {
                showRewindPicker = false
            }
        } catch {
            logger.error("Failed to send rewind selection: \(error.localizedDescription)")
        }
    }

    /// Collect user turns from conversationLines for the rewind picker.
    /// Each `.user` marker starts a new turn (matching desktop's rewind checkpoints).
    private func computeRewindTurns() -> [RewindTurnInfo] {
        var userTurns: [String] = []
        let markerChars: Set<Character> = ["\u{203A}", "\u{00B7}", "\u{23FA}", "\u{276F}", " "]

        // Walk forward — every .user marker is a separate rewind checkpoint
        for line in conversationLines {
            if line.markerRole == .user {
                var preview = line.segments.map(\.text).joined()
                    .trimmingCharacters(in: .whitespaces)
                // Strip leading marker characters (›, ·, ⏺, ❯)
                while let first = preview.first, markerChars.contains(first) {
                    preview.removeFirst()
                }
                preview = preview.trimmingCharacters(in: .whitespaces)
                userTurns.append(String(preview.prefix(80)))
            }
        }

        // Number: most recent user turn = 1, oldest = N
        let total = userTurns.count
        var result: [RewindTurnInfo] = []
        for (index, preview) in userTurns.enumerated() {
            let turnsAgo = total - index
            result.append(RewindTurnInfo(id: turnsAgo, role: "user", preview: preview))
        }

        // Most recent first, limit to 20
        return Array(result.reversed().prefix(20))
    }

    // MARK: - Badge

    /// App icon badge mirrors the number of sessions needing a decision.
    private func updateBadgeCount() {
        let attentionCount = sessions.filter {
            $0.needsAttention || sessionsNeedingAttention.contains($0.id)
        }.count
        UNUserNotificationCenter.current().setBadgeCount(attentionCount)
    }

    // MARK: - Live Activity

    /// Sync the Live Activity with aggregate session counts.
    private func syncLiveActivity() {
        #if canImport(ActivityKit)
        let manager = LiveActivityManager.shared

        guard !sessions.isEmpty else {
            manager.endActivity()
            return
        }

        var working = 0
        var done = 0
        var attention = 0

        for session in sessions {
            let needsAttention = session.needsAttention || sessionsNeedingAttention.contains(session.id)
            let awaitingInput = session.awaitingInput || sessionsAwaitingInput.contains(session.id)

            if needsAttention {
                attention += 1
            } else if awaitingInput {
                done += 1
            } else {
                working += 1
            }
        }

        manager.syncActivity(
            workingCount: working,
            doneCount: done,
            attentionCount: attention,
            totalCount: sessions.count
        )
        #endif
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: BalconyMessage) {
        switch message.type {
        case .sessionList:
            handleSessionList(message)
        case .terminalData:
            handleTerminalData(message)
        case .transcriptEvents:
            handleTranscriptEvents(message)
        case .slashCommands:
            handleSlashCommands(message)
        case .fileList:
            handleFileList(message)
        case .sessionPickerShow:
            handleSessionPicker(message)
        case .modelPickerShow:
            handleModelPicker(message)
        case .hookEvent:
            handleHookEvent(message)
        case .hookDismiss:
            handleHookDismiss(message)
        case .idlePrompt:
            handleIdlePrompt(message)
        case .idlePromptDismiss:
            handleIdlePromptDismiss(message)
        case .askUserQuestion:
            handleAskUserQuestion(message)
        case .askUserQuestionDismiss:
            handleAskUserQuestionDismiss(message)
        default:
            break
        }
    }

    private func handleSessionList(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SessionListPayload.self)
            let oldSessions = sessions

            // Check for session state transitions before replacing.
            // The master switch (sidebar, auto-arms when away) gates system
            // notifications only; in-app cues (sound + toast) fire whenever
            // the app is active so background sessions stay visible.
            let defaults = UserDefaults.standard
            let notificationsOn = defaults.bool(forKey: "notificationsEnabled")
            // Per-type gates from Settings ▸ Notifications (default on).
            let toolApprovalsOn = defaults.object(forKey: "notify.toolApprovals") as? Bool ?? true
            let sessionCompleteOn = defaults.object(forKey: "notify.sessionComplete") as? Bool ?? true
            let appIsInactive = UIApplication.shared.applicationState != .active

            for newSession in payload.sessions {
                if let old = oldSessions.first(where: { $0.id == newSession.id }) {
                    let isMuted = mutedSessionIds.contains(newSession.id)
                    let attentionTransition = !old.needsAttention && newSession.needsAttention && toolApprovalsOn && !isMuted
                    let inputTransition = !old.awaitingInput && newSession.awaitingInput && sessionCompleteOn && !isMuted
                    let isBackground = newSession.id != activeSession?.id

                    if attentionTransition {
                        if appIsInactive {
                            if notificationsOn {
                                NotificationManager.shared.notifySessionEvent(
                                    sessionId: newSession.id,
                                    sessionName: newSession.projectName,
                                    message: "Needs your attention — permission prompt or question",
                                    sound: SoundManager.shared.attentionSound.notificationSound
                                )
                            }
                        } else if isBackground {
                            SoundManager.shared.playAttentionSound()
                            attentionToast = AttentionToast(
                                sessionId: newSession.id,
                                sessionName: newSession.projectName,
                                message: "Needs your attention",
                                isAttention: true
                            )
                        }
                        break
                    }
                    if inputTransition {
                        if appIsInactive {
                            if notificationsOn {
                                NotificationManager.shared.notifySessionEvent(
                                    sessionId: newSession.id,
                                    sessionName: newSession.projectName,
                                    message: "Claude finished — waiting for your next prompt",
                                    sound: SoundManager.shared.doneSound.notificationSound
                                )
                            }
                        } else if isBackground {
                            SoundManager.shared.playDoneSound()
                            attentionToast = AttentionToast(
                                sessionId: newSession.id,
                                sessionName: newSession.projectName,
                                message: "Finished — your turn",
                                isAttention: false
                            )
                        }
                        break
                    }
                }
            }

            sessions = payload.sessions
            logger.info("Received session list: \(payload.sessions.count) sessions")

            // If the active session was removed (CLI exited), clean up local state
            // so the UI navigates back to the session list.
            if let active = activeSession,
               !payload.sessions.contains(where: { $0.id == active.id }) {
                logger.info("Active session \(active.id) ended remotely — cleaning up")
                activeSession = nil
                parserCancellable?.cancel()
                parserCancellable = nil
                promptCancellable?.cancel()
                promptCancellable = nil
                pendingInputCancellable?.cancel()
                pendingInputCancellable = nil
                parser = nil
                conversationLines = []
                transcriptEvents = []
                activePrompt = nil
                pendingHookData = nil
                pendingIdlePrompt = nil
                pendingAskUserQuestion = nil
                pendingInputText = ""
                projectFiles = []
                sessionsNeedingAttention.remove(active.id)
                sessionsAwaitingInput.remove(active.id)
            }
            // Clean up sets for any sessions that no longer exist
            let currentIds = Set(payload.sessions.map(\.id))
            sessionsNeedingAttention.formIntersection(currentIds)
            sessionsAwaitingInput.formIntersection(currentIds)

            syncLiveActivity()
            updateBadgeCount()
        } catch {
            logger.error("Failed to decode session list: \(error.localizedDescription)")
        }
    }

    private func handleTerminalData(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(TerminalDataPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            parser?.feed(data: payload.data)
            logger.debug("Terminal data for \(payload.sessionId): \(payload.data.count) bytes")
        } catch {
            logger.error("Failed to decode terminal data: \(error.localizedDescription)")
        }
    }

    private func handleTranscriptEvents(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(TranscriptEventsPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            if payload.reset {
                transcriptEvents = payload.events
            } else {
                // Append, de-duplicating by event id (defends against snapshot/
                // delta overlap on reconnect).
                let existing = Set(transcriptEvents.map(\.id))
                transcriptEvents.append(contentsOf: payload.events.filter { !existing.contains($0.id) })
            }
            logger.debug("Transcript events for \(payload.sessionId): +\(payload.events.count) reset=\(payload.reset)")
        } catch {
            logger.error("Failed to decode transcript events: \(error.localizedDescription)")
        }
    }

    private func handleSlashCommands(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SlashCommandsPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            slashCommands = payload.commands
            logger.info("Received \(payload.commands.count) slash commands")
        } catch {
            logger.error("Failed to decode slash commands: \(error.localizedDescription)")
        }
    }

    private func handleFileList(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(FileListPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            projectFiles = payload.files
            logger.info("Received \(payload.files.count) project files")
        } catch {
            logger.error("Failed to decode file list: \(error.localizedDescription)")
        }
    }

    private func handleSessionPicker(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SessionPickerPayload.self)
            availableSessions = payload.sessions
            pickerPTYSessionId = payload.ptySessionId
            withAnimation(BalconyTheme.springSnappy) {
                showSessionPicker = true
            }
            logger.info("Received \(payload.sessions.count) sessions for picker")
        } catch {
            logger.error("Failed to decode session picker: \(error.localizedDescription)")
        }
    }

    private func handleModelPicker(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(ModelPickerPayload.self)
            availableModels = payload.models
            currentModelId = payload.currentModelId
            modelPickerPTYSessionId = payload.ptySessionId
            withAnimation(BalconyTheme.springSnappy) {
                showModelPicker = true
            }
            logger.info("Received \(payload.models.count) models for picker (current: \(payload.currentModelId ?? "none"))")
        } catch {
            logger.error("Failed to decode model picker: \(error.localizedDescription)")
        }
    }

    private func handleHookEvent(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(HookEventPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            // Track for sidebar dot using activeSession.id (PTY session ID)
            if let sid = activeSession?.id {
                sessionsNeedingAttention.insert(sid); updateBadgeCount()
                sessionsAwaitingInput.remove(sid)
            }
            pendingHookData = payload
            syncLiveActivity()
            logger.info("Received hook event: \(payload.toolName) session=\(payload.sessionId)")
        } catch {
            logger.error("Failed to decode hook event: \(error.localizedDescription)")
        }
    }

    private func handleHookDismiss(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(HookDismissPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            if let sid = activeSession?.id {
                sessionsNeedingAttention.remove(sid); updateBadgeCount()
            }
            pendingHookData = nil
            syncLiveActivity()
            logger.info("Hook prompt dismissed for session: \(payload.sessionId)")
        } catch {
            logger.error("Failed to decode hook dismiss: \(error.localizedDescription)")
        }
    }

    private func handleIdlePrompt(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(IdlePromptPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            // Track for sidebar dot — idle means "your turn to type"
            if let sid = activeSession?.id {
                sessionsAwaitingInput.insert(sid)
                sessionsNeedingAttention.remove(sid); updateBadgeCount()
            }
            pendingIdlePrompt = payload
            syncLiveActivity()
            logger.info("Received idle prompt: session=\(payload.sessionId)")
        } catch {
            logger.error("Failed to decode idle prompt: \(error.localizedDescription)")
        }
    }

    private func handleIdlePromptDismiss(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(HookDismissPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            if let sid = activeSession?.id {
                sessionsAwaitingInput.remove(sid)
            }
            pendingIdlePrompt = nil
            syncLiveActivity()
            logger.info("Idle prompt dismissed for session: \(payload.sessionId)")
        } catch {
            logger.error("Failed to decode idle prompt dismiss: \(error.localizedDescription)")
        }
    }

    private func handleAskUserQuestion(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(AskUserQuestionPayload.self)
            guard payload.ptySessionId == activeSession?.id else { return }
            // Track for sidebar dot
            if let sid = activeSession?.id {
                sessionsNeedingAttention.insert(sid); updateBadgeCount()
                sessionsAwaitingInput.remove(sid)
            }
            pendingAskUserQuestion = payload
            syncLiveActivity()
            logger.info("Received AskUserQuestion: \(payload.questions.count) question(s) pty=\(payload.ptySessionId ?? "nil")")
        } catch {
            logger.error("Failed to decode AskUserQuestion: \(error.localizedDescription)")
        }
    }

    private func handleAskUserQuestionDismiss(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(AskUserQuestionDismissPayload.self)
            guard payload.ptySessionId == activeSession?.id else { return }
            if let sid = activeSession?.id {
                sessionsNeedingAttention.remove(sid); updateBadgeCount()
            }
            pendingAskUserQuestion = nil
            syncLiveActivity()
            logger.info("AskUserQuestion dismissed for session: \(payload.ptySessionId ?? "nil")")
        } catch {
            logger.error("Failed to decode AskUserQuestion dismiss: \(error.localizedDescription)")
        }
    }

    /// Submit AskUserQuestion answers back to Mac.
    func submitAskUserQuestionResponse(answers: [String: String]) async {
        guard let question = pendingAskUserQuestion,
              let connectionManager else { return }
        do {
            let payload = AskUserQuestionResponsePayload(sessionId: question.sessionId, answers: answers)
            let msg = try BalconyMessage.create(type: .askUserQuestionResponse, payload: payload)
            try await connectionManager.send(msg)
            pendingAskUserQuestion = nil
            logger.info("Sent AskUserQuestion response for session: \(question.sessionId)")
        } catch {
            logger.error("Failed to send AskUserQuestion response: \(error.localizedDescription)")
        }
    }

    /// Dismiss AskUserQuestion card without answering.
    func dismissAskUserQuestion() {
        pendingAskUserQuestion = nil
    }
}

// MARK: - Message Payloads

struct EmptyPayload: Codable, Sendable {}

struct SessionListPayload: Codable, Sendable {
    let sessions: [Session]
}

struct SessionSubscribePayload: Codable, Sendable {
    let sessionId: String
}

struct UserInputPayload: Codable, Sendable {
    let sessionId: String
    let text: String
}
