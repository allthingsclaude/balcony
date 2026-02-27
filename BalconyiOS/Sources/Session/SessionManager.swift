import Foundation
import BalconyShared
import Combine
import os

/// Manages Claude Code sessions received from the connected Mac.
@MainActor
final class SessionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "SessionManager")

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?

    /// Parsed conversation lines from the headless terminal parser.
    @Published var conversationLines: [TerminalLine] = []

    /// Slash commands available for the active session.
    @Published var slashCommands: [SlashCommandInfo] = []

    /// Project files for the active session (@ file picker).
    @Published var projectFiles: [String] = []

    /// Detected interactive prompt (permission or multi-option) from terminal output.
    @Published var activePrompt: InteractivePrompt?

    /// Structured hook data for the current permission prompt (from Mac hook listener).
    @Published var pendingHookData: HookEventPayload?

    /// Idle prompt data (Claude waiting for user input, from Mac hook listener).
    @Published var pendingIdlePrompt: IdlePromptPayload?

    /// Text currently in the Mac's input box (after ❯). Used to pre-fill the iOS input.
    @Published var pendingInputText: String = ""

    /// Available sessions for native session picker (/resume command).
    @Published var availableSessions: [SessionInfo] = []

    /// Show the native session picker UI.
    @Published var showSessionPicker: Bool = false

    /// The PTY session ID that triggered the session picker (for routing selection back).
    private var pickerPTYSessionId: String?

    /// Available models for native model picker (/model command).
    @Published var availableModels: [ModelInfo] = []

    /// The currently active model ID (detected from session JSONL).
    @Published var currentModelId: String?

    /// Show the native model picker UI.
    @Published var showModelPicker: Bool = false

    /// The PTY session ID that triggered the model picker (for routing selection back).
    private var modelPickerPTYSessionId: String?

    /// Computed rewind turns for native rewind picker (/rewind command).
    @Published var rewindTurns: [RewindTurnInfo] = []

    /// Show the native rewind picker UI.
    @Published var showRewindPicker: Bool = false

    private var parser: HeadlessTerminalParser?
    private var parserCancellable: AnyCancellable?
    private var promptCancellable: AnyCancellable?
    private var pendingInputCancellable: AnyCancellable?

    private weak var connectionManager: ConnectionManager?

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
            pendingInputText = ""
            projectFiles = []
        }

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
        showSessionPicker = false
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
            showSessionPicker = false
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
        showModelPicker = false
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
            showModelPicker = false
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
        showRewindPicker = true
    }

    /// Dismiss the rewind picker without selecting.
    func dismissRewindPicker() {
        showRewindPicker = false
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
            showRewindPicker = false
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

    // MARK: - Message Handling

    private func handleMessage(_ message: BalconyMessage) {
        switch message.type {
        case .sessionList:
            handleSessionList(message)
        case .sessionUpdate:
            handleSessionUpdate(message)
        case .terminalData:
            handleTerminalData(message)
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
        default:
            break
        }
    }

    private func handleSessionList(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SessionListPayload.self)
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
                activePrompt = nil
                pendingHookData = nil
                pendingIdlePrompt = nil
                pendingInputText = ""
                projectFiles = []
            }
        } catch {
            logger.error("Failed to decode session list: \(error.localizedDescription)")
        }
    }

    private func handleSessionUpdate(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SessionUpdatePayload.self)
            if let index = sessions.firstIndex(where: { $0.id == payload.session.id }) {
                sessions[index] = payload.session
            } else {
                sessions.append(payload.session)
            }
            if activeSession?.id == payload.session.id {
                activeSession = payload.session
            }
            logger.debug("Session updated: \(payload.session.id)")
        } catch {
            logger.error("Failed to decode session update: \(error.localizedDescription)")
        }
    }

    private func handleTerminalData(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(TerminalDataPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            parser?.feed(bytes: Array(payload.data))
            logger.debug("Terminal data for \(payload.sessionId): \(payload.data.count) bytes")
        } catch {
            logger.error("Failed to decode terminal data: \(error.localizedDescription)")
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
            showSessionPicker = true
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
            showModelPicker = true
            logger.info("Received \(payload.models.count) models for picker (current: \(payload.currentModelId ?? "none"))")
        } catch {
            logger.error("Failed to decode model picker: \(error.localizedDescription)")
        }
    }

    private func handleHookEvent(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(HookEventPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            pendingHookData = payload
            logger.info("Received hook event: \(payload.toolName) session=\(payload.sessionId)")
        } catch {
            logger.error("Failed to decode hook event: \(error.localizedDescription)")
        }
    }

    private func handleHookDismiss(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(HookDismissPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            pendingHookData = nil
            logger.info("Hook prompt dismissed for session: \(payload.sessionId)")
        } catch {
            logger.error("Failed to decode hook dismiss: \(error.localizedDescription)")
        }
    }

    private func handleIdlePrompt(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(IdlePromptPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            pendingIdlePrompt = payload
            logger.info("Received idle prompt: session=\(payload.sessionId)")
        } catch {
            logger.error("Failed to decode idle prompt: \(error.localizedDescription)")
        }
    }

    private func handleIdlePromptDismiss(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(HookDismissPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            pendingIdlePrompt = nil
            logger.info("Idle prompt dismissed for session: \(payload.sessionId)")
        } catch {
            logger.error("Failed to decode idle prompt dismiss: \(error.localizedDescription)")
        }
    }
}

// MARK: - Message Payloads

struct EmptyPayload: Codable, Sendable {}

struct SessionListPayload: Codable, Sendable {
    let sessions: [Session]
}

struct SessionUpdatePayload: Codable, Sendable {
    let session: Session
}

struct SessionSubscribePayload: Codable, Sendable {
    let sessionId: String
}

struct UserInputPayload: Codable, Sendable {
    let sessionId: String
    let text: String
}
