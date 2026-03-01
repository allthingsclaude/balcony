import Foundation
import BalconyShared
import os

/// Coordinates all connection components (WebSocket, Bonjour, BLE)
/// and bridges PTY session data to connected iOS clients.
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "ConnectionManager")

    @Published var connectedDevices: [DeviceInfo] = []
    @Published var isServerRunning = false

    /// Icon name reflecting current connection state for the menu bar.
    var statusIconName: String {
        if !isServerRunning {
            return "antenna.radiowaves.left.and.right.slash"
        } else if !connectedDevices.isEmpty {
            return "antenna.radiowaves.left.and.right.circle.fill"
        } else {
            return "antenna.radiowaves.left.and.right"
        }
    }

    private let webSocketServer: WebSocketServer
    private let bonjourAdvertiser: BonjourAdvertiser
    private let blePeripheral: BLEPeripheral
    private let ptySessionManager: PTYSessionManager

    /// Server identity crypto manager used for QR code pairing.
    let serverCrypto = CryptoManager()
    private let port: Int
    private let encoder = MessageEncoder()
    private var serverEventTask: Task<Void, Never>?

    /// Weak reference to AppDelegate for session picker notifications.
    weak var appDelegate: AppDelegate?

    /// Weak reference to HookEventHandler for resending pending prompts on reconnect.
    weak var hookEventHandler: HookEventHandler?

    init(
        port: Int = 29170,
        ptySessionManager: PTYSessionManager
    ) {
        self.port = port
        self.webSocketServer = WebSocketServer(port: port)
        self.bonjourAdvertiser = BonjourAdvertiser(port: UInt16(port))
        self.blePeripheral = BLEPeripheral()
        self.ptySessionManager = ptySessionManager
    }

    /// Generate the pairing URL containing host, port, and public key.
    func generatePairingURL() async throws -> String {
        _ = try await serverCrypto.generateKeyPair()
        let publicKeyBase64 = try await serverCrypto.publicKeyBase64()
        let host = ProcessInfo.processInfo.hostName
        var components = URLComponents()
        components.scheme = "balcony"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "pk", value: publicKeyBase64),
        ]
        return components.string ?? "balcony://pair?host=\(host)&port=\(port)&pk=\(publicKeyBase64)"
    }

    // MARK: - Lifecycle

    func start() async throws {
        logger.info("Starting connection services")

        let serverEvents = try await webSocketServer.start()
        serverEventTask = Task { [weak self] in
            for await event in serverEvents {
                await self?.handleServerEvent(event)
            }
        }

        let keyPair = try await serverCrypto.generateKeyPair()
        bonjourAdvertiser.startAdvertising(publicKeyFingerprint: keyPair.fingerprint)
        blePeripheral.startAdvertising(deviceName: Host.current().localizedName ?? "Mac")

        isServerRunning = true
        logger.info("All connection services started")
    }

    func stop() async throws {
        serverEventTask?.cancel()
        serverEventTask = nil
        try await webSocketServer.stop()
        bonjourAdvertiser.stopAdvertising()
        blePeripheral.stopAdvertising()
        connectedDevices = []
        isServerRunning = false
        logger.info("All connection services stopped")
    }

    // MARK: - PTY Data Forwarding

    /// Forward raw PTY output from a CLI session to WebSocket subscribers.
    func forwardPTYOutput(sessionId: String, data: Data) async {
        do {
            let payload = TerminalDataPayload(sessionId: sessionId, data: data)
            let msg = try BalconyMessage.create(type: .terminalData, payload: payload)
            await webSocketServer.sendToSubscribers(of: sessionId, message: msg)
        } catch {
            logger.error("Failed to forward PTY output: \(error.localizedDescription)")
        }
    }

    /// Check if any iOS clients are currently connected.
    func hasConnectedClients() async -> Bool {
        return !connectedDevices.isEmpty
    }

    // MARK: - Hook Event Forwarding

    /// Forward a permission prompt info to subscribed iOS clients.
    func forwardHookEvent(_ promptInfo: PermissionPromptInfo) async {
        do {
            let payload = HookEventPayload(from: promptInfo)
            let msg = try BalconyMessage.create(type: .hookEvent, payload: payload)
            await webSocketServer.sendToSubscribers(of: promptInfo.sessionId, message: msg)
            logger.info("Forwarded hook event to iOS: \(promptInfo.toolName) session=\(promptInfo.sessionId)")
        } catch {
            logger.error("Failed to forward hook event: \(error.localizedDescription)")
        }
    }

    /// Resend pending hook event to a specific client (for reconnect sync).
    private func resendPendingHookEvent(sessionId: String, to client: ConnectedClient) async {
        guard let info = hookEventHandler?.pendingPrompt(for: sessionId) else { return }
        do {
            let payload = HookEventPayload(from: info)
            let msg = try BalconyMessage.create(type: .hookEvent, payload: payload)
            await webSocketServer.send(msg, to: client)
            logger.info("Resent pending hook event on reconnect: \(info.toolName) session=\(sessionId)")
        } catch {
            logger.error("Failed to resend hook event: \(error.localizedDescription)")
        }
    }

    /// Notify iOS clients that a permission prompt was dismissed.
    func forwardHookDismiss(sessionId: String) async {
        do {
            let payload = HookDismissPayload(sessionId: sessionId)
            let msg = try BalconyMessage.create(type: .hookDismiss, payload: payload)
            await webSocketServer.sendToSubscribers(of: sessionId, message: msg)
            logger.info("Forwarded hook dismiss to iOS: session=\(sessionId)")
        } catch {
            logger.error("Failed to forward hook dismiss: \(error.localizedDescription)")
        }
    }

    /// Forward an idle prompt (Claude waiting for input) to subscribed iOS clients.
    func forwardIdlePrompt(_ info: IdlePromptInfo) async {
        do {
            let payload = IdlePromptPayload(from: info)
            let msg = try BalconyMessage.create(type: .idlePrompt, payload: payload)
            await webSocketServer.sendToSubscribers(of: info.sessionId, message: msg)
            logger.info("Forwarded idle prompt to iOS: session=\(info.sessionId)")
        } catch {
            logger.error("Failed to forward idle prompt: \(error.localizedDescription)")
        }
    }

    // MARK: - AskUserQuestion Forwarding

    /// Forward an AskUserQuestion to subscribed iOS clients.
    /// Routes using the PTY session ID (what iOS subscribes to).
    func forwardAskUserQuestion(_ info: AskUserQuestionInfo) async {
        guard let ptySessionId = info.ptySessionId else {
            logger.debug("Skipping AskUserQuestion forward — no PTY session ID")
            return
        }
        do {
            let payload = AskUserQuestionPayload(from: info)
            let msg = try BalconyMessage.create(type: .askUserQuestion, payload: payload)
            await webSocketServer.sendToSubscribers(of: ptySessionId, message: msg)
            logger.info("Forwarded AskUserQuestion to iOS: \(info.questions.count) question(s) pty=\(ptySessionId)")
        } catch {
            logger.error("Failed to forward AskUserQuestion: \(error.localizedDescription)")
        }
    }

    /// Notify iOS clients that an AskUserQuestion was dismissed.
    /// Routes using the PTY session ID (what iOS subscribes to).
    func forwardAskUserQuestionDismiss(sessionId: String, ptySessionId: String?) async {
        guard let ptySessionId else {
            logger.debug("Skipping AskUserQuestion dismiss forward — no PTY session ID")
            return
        }
        do {
            let payload = AskUserQuestionDismissPayload(sessionId: sessionId, ptySessionId: ptySessionId)
            let msg = try BalconyMessage.create(type: .askUserQuestionDismiss, payload: payload)
            await webSocketServer.sendToSubscribers(of: ptySessionId, message: msg)
            logger.info("Forwarded AskUserQuestion dismiss to iOS: pty=\(ptySessionId)")
        } catch {
            logger.error("Failed to forward AskUserQuestion dismiss: \(error.localizedDescription)")
        }
    }

    /// Resend pending AskUserQuestion to a specific client (for reconnect sync).
    /// The `sessionId` here is the PTY session ID (from sessionSubscribe).
    private func resendPendingAskUserQuestion(sessionId: String, to client: ConnectedClient) async {
        guard let info = hookEventHandler?.pendingAskUserQuestion(forPTYSession: sessionId) else { return }
        do {
            let payload = AskUserQuestionPayload(from: info)
            let msg = try BalconyMessage.create(type: .askUserQuestion, payload: payload)
            await webSocketServer.send(msg, to: client)
            logger.info("Resent pending AskUserQuestion on reconnect: pty=\(sessionId)")
        } catch {
            logger.error("Failed to resend AskUserQuestion: \(error.localizedDescription)")
        }
    }

    /// Notify iOS clients that an idle prompt was dismissed.
    func forwardIdlePromptDismiss(sessionId: String) async {
        do {
            let payload = HookDismissPayload(sessionId: sessionId)
            let msg = try BalconyMessage.create(type: .idlePromptDismiss, payload: payload)
            await webSocketServer.sendToSubscribers(of: sessionId, message: msg)
            logger.info("Forwarded idle prompt dismiss to iOS: session=\(sessionId)")
        } catch {
            logger.error("Failed to forward idle prompt dismiss: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Event Forwarding

    /// Forward a PTY session event to connected iOS clients.
    func forwardSessionEvent(_ event: SessionEvent) async {
        switch event {
        case .sessionDiscovered:
            await broadcastSessionList()
        case .sessionEnded:
            await broadcastSessionList()
        }
    }

    // MARK: - Server Event Handling

    private func handleServerEvent(_ event: WebSocketServerEvent) async {
        switch event {
        case .clientConnected(let client):
            logger.info("Client connected: \(client.id)")

        case .clientAuthenticated(let client, let deviceInfo):
            connectedDevices.append(deviceInfo)
            logger.info("Client authenticated: \(deviceInfo.name)")
            await sendSessionList(to: client)

        case .clientDisconnected(let client):
            if let info = client.deviceInfo {
                connectedDevices.removeAll { $0.id == info.id }
            }
            logger.info("Client disconnected: \(client.id)")

        case .messageReceived(let client, let message):
            await handleClientMessage(from: client, message: message)
        }
    }

    private func handleClientMessage(from client: ConnectedClient, message: BalconyMessage) async {
        switch message.type {
        case .sessionList:
            await sendSessionList(to: client)

        case .sessionSubscribe:
            do {
                let payload = try message.decodePayload(SessionSubscribePayload.self)
                let sessionId = payload.sessionId
                logger.info("Client subscribed to PTY session \(sessionId)")

                // Send buffered PTY history so iOS gets the full conversation.
                // Chunk large buffers to avoid exceeding WebSocket message size limits.
                if let buffer = await ptySessionManager.getSessionBuffer(sessionId), !buffer.isEmpty {
                    let chunkSize = 512 * 1024 // 512 KB raw → ~750 KB after base64/JSON encoding
                    var offset = 0
                    while offset < buffer.count {
                        let end = min(offset + chunkSize, buffer.count)
                        let chunk = buffer[offset..<end]
                        let historyPayload = TerminalDataPayload(sessionId: sessionId, data: Data(chunk))
                        let historyMsg = try BalconyMessage.create(type: .terminalData, payload: historyPayload)
                        await webSocketServer.send(historyMsg, to: client)
                        offset = end
                    }
                }

                // Send available slash commands for this session's project.
                await sendSlashCommands(sessionId: sessionId, to: client)

                // Send project file list for the @ file picker.
                await sendFileList(sessionId: sessionId, to: client)

                // Resend pending hook data if a prompt is active for this session.
                // This handles reconnect: iOS disconnects and reconnects while
                // a permission prompt is waiting — the prompt is resent immediately.
                await resendPendingHookEvent(sessionId: sessionId, to: client)

                // Resend pending AskUserQuestion if one is active.
                await resendPendingAskUserQuestion(sessionId: sessionId, to: client)
            } catch {
                logger.error("Failed to decode session subscribe: \(error.localizedDescription)")
            }

        case .userInput:
            do {
                let input = try message.decodePayload(UserInputPayload.self)
                if let data = input.text.data(using: .utf8) {
                    await ptySessionManager.sendInput(sessionId: input.sessionId, data: data)
                }
                logger.info("Delivered input to PTY for session \(input.sessionId)")

                // Dismiss Mac panels — iOS answered the prompt so the local panel is stale.
                // Resolve PTY session ID to Claude session IDs for prompt lookup.
                await MainActor.run {
                    hookEventHandler?.handleStdinActivity(ptySessionId: input.sessionId)
                }
            } catch {
                logger.error("Failed to deliver user input: \(error.localizedDescription)")
            }

        case .terminalResize:
            do {
                let payload = try message.decodePayload(TerminalResizePayload.self)
                await ptySessionManager.sendResize(
                    sessionId: payload.sessionId,
                    cols: payload.cols,
                    rows: payload.rows
                )
            } catch {
                logger.error("Failed to forward terminal resize: \(error.localizedDescription)")
            }

        case .sessionPickerRequest:
            do {
                let payload = try message.decodePayload(SessionPickerRequestPayload.self)
                await appDelegate?.handleSessionPickerRequest(ptySessionId: payload.ptySessionId)
            } catch {
                logger.error("Failed to handle session picker request: \(error.localizedDescription)")
            }

        case .sessionPickerSelection:
            do {
                let payload = try message.decodePayload(SessionPickerSelectionPayload.self)
                await handleSessionSelection(payload: payload, client: client)
            } catch {
                logger.error("Failed to handle session picker selection: \(error.localizedDescription)")
            }

        case .modelPickerRequest:
            do {
                let payload = try message.decodePayload(ModelPickerRequestPayload.self)
                await appDelegate?.handleModelPickerRequest(ptySessionId: payload.ptySessionId)
            } catch {
                logger.error("Failed to handle model picker request: \(error.localizedDescription)")
            }

        case .modelPickerSelection:
            do {
                let payload = try message.decodePayload(ModelPickerSelectionPayload.self)
                await handleModelSelection(payload: payload, client: client)
            } catch {
                logger.error("Failed to handle model picker selection: \(error.localizedDescription)")
            }

        case .rewindSelection:
            do {
                let payload = try message.decodePayload(RewindSelectionPayload.self)
                await handleRewindSelection(payload: payload, client: client)
            } catch {
                logger.error("Failed to handle rewind selection: \(error.localizedDescription)")
            }

        case .askUserQuestionResponse:
            do {
                let payload = try message.decodePayload(AskUserQuestionResponsePayload.self)
                await appDelegate?.handleAskUserQuestionResponse(sessionId: payload.sessionId, answers: payload.answers)
            } catch {
                logger.error("Failed to handle AskUserQuestion response: \(error.localizedDescription)")
            }

        default:
            logger.debug("Unhandled client message type: \(message.type.rawValue)")
        }
    }

    // MARK: - Slash Commands

    private func sendSlashCommands(sessionId: String, to client: ConnectedClient) async {
        let sessions = await ptySessionManager.getActiveSessions()
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        let projectPath = session.projectPath
        let commands = SlashCommandScanner.scan(projectPath: projectPath)

        do {
            let payload = SlashCommandsPayload(sessionId: sessionId, commands: commands)
            let msg = try BalconyMessage.create(type: .slashCommands, payload: payload)
            await webSocketServer.send(msg, to: client)
            logger.info("Sent \(commands.count) slash commands for session \(sessionId)")
        } catch {
            logger.error("Failed to send slash commands: \(error.localizedDescription)")
        }
    }

    // MARK: - File List

    private func sendFileList(sessionId: String, to client: ConnectedClient) async {
        let sessions = await ptySessionManager.getActiveSessions()
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        let files = ProjectFileScanner.scan(projectPath: session.projectPath)
        do {
            let payload = FileListPayload(sessionId: sessionId, files: files)
            let msg = try BalconyMessage.create(type: .fileList, payload: payload)
            await webSocketServer.send(msg, to: client)
            logger.info("Sent \(files.count) project files for session \(sessionId)")
        } catch {
            logger.error("Failed to send file list: \(error.localizedDescription)")
        }
    }

    // MARK: - Session List

    private func broadcastSessionList() async {
        let sessions = await ptySessionManager.getActiveSessions()
        do {
            let payload = SessionListPayload(sessions: sessions)
            let msg = try BalconyMessage.create(type: .sessionList, payload: payload)
            await webSocketServer.broadcast(msg)
        } catch {
            logger.error("Failed to broadcast session list: \(error.localizedDescription)")
        }
    }

    private func sendSessionList(to client: ConnectedClient) async {
        let sessions = await ptySessionManager.getActiveSessions()
        do {
            let payload = SessionListPayload(sessions: sessions)
            let msg = try BalconyMessage.create(type: .sessionList, payload: payload)
            await webSocketServer.send(msg, to: client)
        } catch {
            logger.error("Failed to send session list to \(client.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Session Picker

    /// Send available sessions to iOS for native session picker (/resume command).
    func sendSessionPicker(ptySessionId: String, projectPath: String, sessions: [SessionInfo]) async {
        do {
            let payload = SessionPickerPayload(ptySessionId: ptySessionId, projectPath: projectPath, sessions: sessions)
            let msg = try BalconyMessage.create(type: .sessionPickerShow, payload: payload)
            await webSocketServer.sendToSubscribers(of: ptySessionId, message: msg)
            logger.info("Sent session picker with \(sessions.count) sessions to iOS")
        } catch {
            logger.error("Failed to send session picker: \(error.localizedDescription)")
        }
    }

    // MARK: - Model Picker

    /// Send available models to iOS for native model picker (/model command).
    func sendModelPicker(ptySessionId: String, currentModelId: String?, models: [ModelInfo]) async {
        do {
            let payload = ModelPickerPayload(ptySessionId: ptySessionId, currentModelId: currentModelId, models: models)
            let msg = try BalconyMessage.create(type: .modelPickerShow, payload: payload)
            await webSocketServer.sendToSubscribers(of: ptySessionId, message: msg)
            logger.info("Sent model picker with \(models.count) models to iOS")
        } catch {
            logger.error("Failed to send model picker: \(error.localizedDescription)")
        }
    }

    /// Handle model selection from iOS - send the selected model ID to the terminal.
    private func handleModelSelection(payload: ModelPickerSelectionPayload, client: ConnectedClient) async {
        logger.info("Handling model selection: \(payload.modelId) for PTY \(payload.ptySessionId)")

        let sessions = await ptySessionManager.getActiveSessions()
        guard let activeSession = sessions.first(where: { $0.id == payload.ptySessionId }) else {
            logger.warning("No active PTY session found for id \(payload.ptySessionId)")
            return
        }

        // Send the /model command text first, then Enter separately.
        let commandText = "/model \(payload.modelId)"
        if let textData = commandText.data(using: .utf8) {
            await ptySessionManager.sendInput(sessionId: activeSession.id, data: textData)
        }

        // Brief delay then send Enter
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        if let enterData = "\r".data(using: .utf8) {
            await ptySessionManager.sendInput(sessionId: activeSession.id, data: enterData)
            logger.info("Sent model command for model: \(payload.modelId)")
        }
    }

    /// Handle session selection from iOS - send the selected session ID to the terminal.
    private func handleSessionSelection(payload: SessionPickerSelectionPayload, client: ConnectedClient) async {
        logger.info("Handling session selection: \(payload.sessionId) for PTY \(payload.ptySessionId)")

        // Use the PTY session ID from the payload to route the command correctly
        let sessions = await ptySessionManager.getActiveSessions()
        guard let activeSession = sessions.first(where: { $0.id == payload.ptySessionId }) else {
            logger.warning("No active PTY session found for id \(payload.ptySessionId)")
            return
        }

        // Send the resume command text first, then Enter separately.
        // Sending them as one chunk can cause the PTY to not process \r as submit.
        let commandText = "/resume \(payload.sessionId)"
        if let textData = commandText.data(using: .utf8) {
            await ptySessionManager.sendInput(sessionId: activeSession.id, data: textData)
        }

        // Brief delay then send Enter
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        if let enterData = "\r".data(using: .utf8) {
            await ptySessionManager.sendInput(sessionId: activeSession.id, data: enterData)
            logger.info("Sent resume command for session: \(payload.sessionId)")
        }
    }

    /// Handle rewind selection from iOS.
    ///
    /// The desktop `/rewind` command is a two-step interactive flow:
    /// 1. A TUI turn picker appears (arrow keys to navigate, Enter to select)
    /// 2. A confirmation prompt with 5 options (handled by iOS InteractivePrompt)
    ///
    /// We automate step 1 by sending `/rewind`, waiting for the picker to render,
    /// navigating with up-arrow keys, and pressing Enter. The cursor starts at the
    /// most recent turn (bottom), so we press up (turnCount - 1) times.
    private func handleRewindSelection(payload: RewindSelectionPayload, client: ConnectedClient) async {
        logger.info("Handling rewind selection: \(payload.turnCount) turns for PTY \(payload.ptySessionId)")

        let sessions = await ptySessionManager.getActiveSessions()
        guard let activeSession = sessions.first(where: { $0.id == payload.ptySessionId }) else {
            logger.warning("No active PTY session found for id \(payload.ptySessionId)")
            return
        }

        let sessionId = activeSession.id

        // 1. Send /rewind + Enter to open the TUI turn picker
        if let textData = "/rewind".data(using: .utf8) {
            await ptySessionManager.sendInput(sessionId: sessionId, data: textData)
        }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        if let enterData = "\r".data(using: .utf8) {
            await ptySessionManager.sendInput(sessionId: sessionId, data: enterData)
        }

        // 2. Wait for the TUI picker to render
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // 3. Navigate: cursor starts at the most recent turn, press up for older turns
        let arrowPresses = payload.turnCount - 1
        if arrowPresses > 0 {
            let upArrow = "\u{1B}[A" // ESC [ A
            for _ in 0..<arrowPresses {
                if let data = upArrow.data(using: .utf8) {
                    await ptySessionManager.sendInput(sessionId: sessionId, data: data)
                }
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms between presses
            }
        }

        // 4. Brief pause then press Enter to confirm selection
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        if let enterData = "\r".data(using: .utf8) {
            await ptySessionManager.sendInput(sessionId: sessionId, data: enterData)
            logger.info("Navigated rewind picker to \(payload.turnCount) turns back")
        }
    }
}

// MARK: - Message Payloads

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
