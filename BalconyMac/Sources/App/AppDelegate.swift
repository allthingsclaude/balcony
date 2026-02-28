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

    /// Pre-resolved PTY session IDs for idle prompts (Claude session ID → PTY session ID).
    /// Stored when the idle prompt is shown so text responses route to the correct PTY
    /// even after the idle prompt info (with cwd) has been dismissed.
    private var idlePromptPTYMapping: [String: String] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")

        // Ignore SIGPIPE so writing to a closed hook socket returns EPIPE
        // instead of crashing the process (e.g., stale permission panel answered
        // after the hook script already exited).
        signal(SIGPIPE, SIG_IGN)

        // Wire up ConnectionManager to AppDelegate for session picker requests
        connectionManager.appDelegate = self
        connectionManager.hookEventHandler = hookEventHandler

        // Wire hook event handler callbacks
        hookEventHandler.onPromptReceived = { [weak self] promptInfo in
            guard let self else { return }
            // Eagerly resolve and register the PTY↔Claude session mapping
            Task {
                _ = await self.resolvePTYSessionId(claudeSessionId: promptInfo.sessionId, cwd: promptInfo.cwd, ptySessionId: promptInfo.ptySessionId)
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

        // Wire idle prompt callbacks — only show for sessions with a PTY wrapper,
        // since text input requires the PTY bridge to deliver keystrokes.
        hookEventHandler.onIdlePromptReceived = { [weak self] info in
            guard let self else { return }

            // Only show idle prompts for sessions running through the BalconyCLI wrapper,
            // since text input requires the PTY bridge to deliver keystrokes.
            guard let ptyId = info.ptySessionId else {
                self.logger.debug("Skipping idle prompt — not a BalconyCLI-wrapped session: \(info.sessionId)")
                self.hookEventHandler.dismissIdlePrompt(for: info.sessionId)
                return
            }

            self.idlePromptPTYMapping[info.sessionId] = ptyId
            self.hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: info.sessionId)

            if let detected = info.detectedOptions {
                self.promptPanelController.showMultiOptionPrompt(info, options: detected.options)
            } else {
                self.promptPanelController.showIdlePrompt(info)
            }
        }
        hookEventHandler.onForwardIdleToiOS = { [weak self] info in
            guard let self else { return }
            // Only forward if wrapped (ptySessionId present)
            guard info.ptySessionId != nil else { return }
            Task {
                await self.connectionManager.forwardIdlePrompt(info)
            }
        }
        hookEventHandler.onIdlePromptDismissed = { [weak self] sessionId in
            guard let self else { return }
            self.idlePromptPTYMapping.removeValue(forKey: sessionId)
            self.promptPanelController.dismissPrompt(for: sessionId)
            Task {
                await self.connectionManager.forwardIdlePromptDismiss(sessionId: sessionId)
            }
        }

        // Wire idle prompt panel text response to PTY input
        promptPanelController.onTextResponse = { [weak self] sessionId, text in
            guard let self else { return }
            Task {
                let ptySessionId = self.resolveIdlePromptPTYSessionId(sessionId)

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

            // If the prompt is no longer pending (already answered elsewhere), just dismiss the panel.
            guard self.hookEventHandler.hasPendingPrompt(for: sessionId) else {
                self.logger.debug("Ignoring stale panel response for session \(sessionId)")
                return
            }

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

        // Wire multi-option response: send arrow key sequence to PTY
        promptPanelController.onMultiOptionResponse = { [weak self] sessionId, sequence in
            guard let self else { return }
            Task {
                let ptySessionId = self.resolveIdlePromptPTYSessionId(sessionId)

                if let data = sequence.data(using: .utf8) {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: data)
                }
                self.hookEventHandler.dismissIdlePrompt(for: sessionId)
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

            // Dismiss idle prompt when user types in the local terminal
            await ptySessionManager.setOnStdinActivity { [weak self] ptySessionId in
                Task { @MainActor in
                    self?.hookEventHandler.handleStdinActivity(ptySessionId: ptySessionId)
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
    /// Uses the direct PTY session ID from the hook event (injected by BalconyCLI wrapper),
    /// falls back to cwd matching and single-session heuristic.
    private func resolvePTYSessionId(claudeSessionId: String, cwd: String?, ptySessionId: String? = nil) async -> String {
        // Best: direct PTY session ID from BalconyCLI wrapper
        if let ptyId = ptySessionId {
            hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: claudeSessionId)
            return ptyId
        }
        // Fallback: match by working directory
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

    // MARK: - Idle Prompt PTY Resolution

    /// Resolve the PTY session ID for an idle prompt response, using the cached mapping first.
    private func resolveIdlePromptPTYSessionId(_ sessionId: String) -> String {
        if let cached = idlePromptPTYMapping.removeValue(forKey: sessionId) {
            return cached
        }
        return sessionId
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
