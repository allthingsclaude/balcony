import AppKit
import BalconyShared
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AppDelegate")

    let ptySessionManager = PTYSessionManager()
    let hookListener = HookListener()
    let hookEventHandler = HookEventHandler()
    lazy var connectionManager = ConnectionManager(ptySessionManager: ptySessionManager)
    let promptPanelController = PromptPanelController()
    let sessionListModel = SessionListModel()
    let sessionFileReader = SessionFileReader()
    let modelListProvider = ModelListProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")

        // Wire up ConnectionManager to AppDelegate for session picker requests
        connectionManager.appDelegate = self
        connectionManager.hookEventHandler = hookEventHandler

        // Wire hook event handler callbacks
        hookEventHandler.onPromptReceived = { [weak self] promptInfo in
            guard let self else { return }
            // Eagerly resolve and register the PTY↔Claude session mapping
            Task {
                _ = await self.resolvePTYSessionId(claudeSessionId: promptInfo.sessionId, cwd: promptInfo.cwd)
            }
            self.promptPanelController.showPrompt(promptInfo)
        }
        hookEventHandler.onForwardToiOS = { [weak self] promptInfo in
            guard let self else { return }
            Task {
                await self.connectionManager.forwardHookEvent(promptInfo)
            }
        }
        hookEventHandler.onPromptDismissed = { [weak self] sessionId in
            guard let self else { return }
            self.promptPanelController.dismissPrompt(for: sessionId)
            Task {
                await self.connectionManager.forwardHookDismiss(sessionId: sessionId)
            }
        }

        // Wire idle prompt callbacks
        hookEventHandler.onIdlePromptReceived = { [weak self] info in
            guard let self else { return }
            // Eagerly resolve and register the PTY↔Claude session mapping
            Task {
                _ = await self.resolvePTYSessionId(claudeSessionId: info.sessionId, cwd: info.cwd)
            }
            self.promptPanelController.showIdlePrompt(info)
        }
        hookEventHandler.onForwardIdleToiOS = { [weak self] info in
            guard let self else { return }
            Task {
                await self.connectionManager.forwardIdlePrompt(info)
            }
        }
        hookEventHandler.onIdlePromptDismissed = { [weak self] sessionId in
            guard let self else { return }
            self.promptPanelController.dismissPrompt(for: sessionId)
            Task {
                await self.connectionManager.forwardIdlePromptDismiss(sessionId: sessionId)
            }
        }

        // Wire idle prompt panel text response to PTY input
        promptPanelController.onTextResponse = { [weak self] sessionId, text in
            guard let self else { return }
            Task {
                // Resolve the PTY session ID from the idle prompt's cwd
                let cwd = self.hookEventHandler.pendingIdlePrompt(for: sessionId)?.cwd
                let ptySessionId = await self.resolvePTYSessionId(claudeSessionId: sessionId, cwd: cwd)

                // Send the text first, then Enter separately after a brief delay.
                // Writing them as one chunk causes Claude Code's TUI to treat it as
                // a paste event and not process \r as a submit action.
                if let textData = text.data(using: .utf8) {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: textData)
                }
                try? await Task.sleep(for: .milliseconds(50))
                if let enterData = Data([0x0D]) as Data? {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: enterData)
                }
                self.hookEventHandler.dismissIdlePrompt(for: sessionId)
            }
        }

        // Wire panel response: send decision back through the hook connection
        promptPanelController.onResponse = { [weak self] sessionId, keystroke in
            guard let self else { return }
            Task {
                // Map keystroke to hook decision
                let decision: String
                switch keystroke.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "y": decision = "allow"
                case "a": decision = "allow"
                case "n": decision = "deny"
                default: decision = "allow"
                }

                // Send the decision back through the hook socket (unblocks the hook handler script)
                await self.hookListener.sendPermissionResponse(sessionId: sessionId, decision: decision)
                self.hookEventHandler.dismissPrompt(for: sessionId)
            }
        }

        Task {
            // Start PTY session manager (Unix domain socket server)
            do {
                try await ptySessionManager.start()
            } catch {
                logger.error("Failed to start PTY session manager: \(error.localizedDescription)")
            }

            // Start hook listener (Unix domain socket for Claude Code hooks)
            do {
                try await hookListener.start()
            } catch {
                logger.error("Failed to start hook listener: \(error.localizedDescription)")
            }

            // Wire hook events to handler
            await hookListener.setOnHookEvent { [weak self] event in
                Task { @MainActor in
                    self?.hookEventHandler.handleHookEvent(event)
                }
            }

            // Wire PTY session events to connection manager and UI
            await ptySessionManager.setOnSessionEvent { [weak self] event in
                Task { @MainActor in
                    await self?.handleSessionEvent(event)
                }
            }

            await ptySessionManager.setOnPTYOutput { [weak self] sessionId, data in
                Task { @MainActor in
                    self?.hookEventHandler.handlePTYOutput(ptySessionId: sessionId, byteCount: data.count)
                    await self?.connectionManager.forwardPTYOutput(sessionId: sessionId, data: data)
                }
            }

            // Start connection services (WebSocket server, Bonjour, BLE)
            do {
                try await connectionManager.start()
            } catch {
                logger.error("Failed to start connection services: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("BalconyMac terminating")

        Task {
            try? await connectionManager.stop()
            await hookListener.stop()
            await ptySessionManager.stop()
        }
    }

    // MARK: - Session ID Resolution

    /// Resolve a Claude Code session ID to a PTY session ID.
    /// Hook events use Claude Code's session ID, but PTYSessionManager uses the CLI tool's session ID.
    /// We match by working directory since both share the same project path.
    private func resolvePTYSessionId(claudeSessionId: String, cwd: String?) async -> String {
        if let cwd, let ptyId = await ptySessionManager.findSessionIdByCwd(cwd) {
            hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: claudeSessionId)
            return ptyId
        }
        // Fallback: if only one PTY session exists, use it
        let sessions = await ptySessionManager.getActiveSessions()
        if sessions.count == 1, let only = sessions.first {
            hookEventHandler.registerPTYMapping(ptySessionId: only.id, claudeSessionId: claudeSessionId)
            return only.id
        }
        // Last resort: return the Claude session ID as-is
        logger.debug("Could not resolve PTY session for Claude session \(claudeSessionId)")
        return claudeSessionId
    }

    // MARK: - Event Routing

    @MainActor
    private func handleSessionEvent(_ event: SessionEvent) async {
        switch event {
        case .sessionDiscovered(let session):
            logger.info("PTY session discovered: \(session.id)")
        case .sessionEnded(let sessionId):
            logger.info("PTY session ended: \(sessionId)")
            // Clean up any pending prompts for the ended session
            hookEventHandler.sessionEnded(sessionId)
        }

        // Update UI model
        let sessions = await ptySessionManager.getActiveSessions()
        sessionListModel.sessions = sessions

        // Forward to connected iOS clients
        await connectionManager.forwardSessionEvent(event)
    }

    // MARK: - Session Picker

    /// Handle session picker request from iOS (triggered when user submits /resume on iOS).
    @MainActor
    func handleSessionPickerRequest(ptySessionId: String) async {
        logger.info("Session picker requested for PTY session: \(ptySessionId)")

        // Get the project path for this session
        let sessions = await ptySessionManager.getActiveSessions()
        logger.info("Active PTY sessions: \(sessions.count) — ids: \(sessions.map(\.id).joined(separator: ", "))")

        guard let session = sessions.first(where: { $0.id == ptySessionId }) else {
            logger.warning("No PTY session found matching id: \(ptySessionId)")
            return
        }
        let projectPath = session.cwd ?? session.projectPath
        logger.info("Project path for session picker: \(projectPath)")

        // Read available sessions from ~/.claude/projects/
        let availableSessions = await sessionFileReader.listSessions(for: projectPath)

        guard !availableSessions.isEmpty else {
            logger.warning("No Claude Code sessions found for project: \(projectPath)")
            return
        }

        logger.info("Sending \(availableSessions.count) sessions to iOS picker")

        // Send session picker to iOS
        await connectionManager.sendSessionPicker(
            ptySessionId: ptySessionId,
            projectPath: projectPath,
            sessions: availableSessions
        )
    }

    // MARK: - Model Picker

    /// Handle model picker request from iOS (triggered when user submits /model on iOS).
    @MainActor
    func handleModelPickerRequest(ptySessionId: String) async {
        logger.info("Model picker requested for PTY session: \(ptySessionId)")

        // Get the project path for this session
        let sessions = await ptySessionManager.getActiveSessions()
        guard let session = sessions.first(where: { $0.id == ptySessionId }) else {
            logger.warning("No PTY session found matching id: \(ptySessionId)")
            return
        }
        let projectPath = session.cwd ?? session.projectPath

        // Detect current model from JSONL files
        let currentModelId = await modelListProvider.currentModelForProject(projectPath)
        let models = await modelListProvider.models

        logger.info("Sending \(models.count) models to iOS picker (current: \(currentModelId ?? "unknown"))")

        await connectionManager.sendModelPicker(
            ptySessionId: ptySessionId,
            currentModelId: currentModelId,
            models: models
        )
    }
}
