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
            self?.promptPanelController.showPrompt(promptInfo)
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

        // Wire panel response to PTY input
        promptPanelController.onResponse = { [weak self] sessionId, keystroke in
            guard let self else { return }
            Task {
                if let data = keystroke.data(using: .utf8) {
                    await self.ptySessionManager.sendInput(sessionId: sessionId, data: data)
                }
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
                    self?.hookEventHandler.handlePTYOutput(sessionId: sessionId, byteCount: data.count)
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
