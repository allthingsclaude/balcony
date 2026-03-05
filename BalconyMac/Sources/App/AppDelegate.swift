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
    let awayDetector = AwayDetector()
    let setupWindowController = SetupWindowController()

    /// Pre-resolved PTY session IDs for idle prompts (Claude session ID → PTY session ID).
    /// Stored when the idle prompt is shown so text responses route to the correct PTY
    /// even after the idle prompt info (with cwd) has been dismissed.
    private var idlePromptPTYMapping: [String: String] = [:]

    /// Timer that periodically refreshes session message counts.
    private var sessionRefreshTimer: Timer?

    /// Observation token for UserDefaults changes.
    private var defaultsObserver: NSObjectProtocol?

    /// Observation token for re-run setup wizard requests.
    private var setupObserver: NSObjectProtocol?

    /// Whether services have been started.
    private var servicesStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")

        // Ignore SIGPIPE so writing to a closed hook socket returns EPIPE
        // instead of crashing the process (e.g., stale permission panel answered
        // after the hook script already exited).
        signal(SIGPIPE, SIG_IGN)

        // Listen for "Re-run Setup Wizard" requests from PreferencesView
        setupObserver = NotificationCenter.default.addObserver(
            forName: .rerunSetupWizard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.setupWindowController.setupManager.resetSetup()
            self.setupWindowController.showSetupWindow {
                // Services already running, nothing to do on complete
            }
        }

        // Check if first-launch setup is needed
        if !setupWindowController.setupManager.isSetupComplete {
            logger.info("First-launch setup needed, showing wizard")
            setupWindowController.showSetupWindow { [weak self] in
                self?.startServices()
            }
            return
        }

        startServices()
    }

    // MARK: - Sound

    enum SoundCategory { case attention, done }

    private func playSound(_ category: SoundCategory) {
        let soundName: String
        switch category {
        case .attention:
            soundName = PreferencesManager.shared.attentionSound
        case .done:
            soundName = PreferencesManager.shared.doneSound
        }
        if !soundName.isEmpty {
            NSSound(named: NSSound.Name(soundName))?.play()
        }
    }

    // MARK: - Focus

    /// Activate the terminal/IDE app that owns the given session's CLI process
    /// and raise the specific window matching the session's working directory.
    func focusSession(_ sessionId: String) {
        Task {
            let ptyId = hookEventHandler.ptySessionId(for: sessionId) ?? sessionId
            guard let pid = await ptySessionManager.pid(for: ptyId) else { return }

            let sessions = await ptySessionManager.getActiveSessions()
            let cwd = sessions.first(where: { $0.id == ptyId })?.cwd

            guard let app = Self.findParentApp(of: pid),
                  let appURL = app.bundleURL else { return }

            if let cwd {
                // Open the project folder with the app — if VS Code/iTerm already has
                // this folder open, macOS will focus that specific window.
                let folderURL = URL(fileURLWithPath: cwd)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                try? await NSWorkspace.shared.open([folderURL], withApplicationAt: appURL, configuration: config)
            } else {
                app.activate()
            }
        }
    }

    /// Walk the process tree upward from `pid` to find the first NSRunningApplication.
    private static func findParentApp(of pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.bundleIdentifier != nil {
                return app
            }
            let parent = parentPID(of: current)
            if parent <= 1 || parent == current { break }
            current = parent
        }
        return nil
    }

    /// Get the parent PID of a process using sysctl.
    private static func parentPID(of pid: Int32) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return -1 }
        return info.kp_eproc.e_ppid
    }

    // MARK: - Service Startup

    /// Start all core services (PTY, hooks, connections, away detection).
    func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true

        logger.info("Starting services")

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
            self.playSound(.attention)
            if PreferencesManager.shared.showAttentionPanel {
                self.promptPanelController.showPrompt(promptInfo)
            }
        }
        hookEventHandler.onForwardToiOS = { [weak self] promptInfo in
            guard let self else { return }
            Task {
                let ptyId = await self.resolvePTYSessionId(
                    claudeSessionId: promptInfo.sessionId,
                    cwd: promptInfo.cwd,
                    ptySessionId: promptInfo.ptySessionId
                )
                await self.connectionManager.forwardHookEvent(promptInfo, resolvedPTYSessionId: ptyId)
                await self.connectionManager.broadcastSessionList()
            }
        }
        // Wire AskUserQuestion: show rich panel with actual question and options
        hookEventHandler.onAskUserQuestionReceived = { [weak self] askInfo in
            guard let self else { return }
            // Register PTY mapping if available
            if let ptyId = askInfo.ptySessionId {
                self.hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: askInfo.sessionId)
            }
            self.playSound(.attention)
            if PreferencesManager.shared.showAttentionPanel {
                self.promptPanelController.showAskUserQuestion(askInfo)
            }
        }
        // Forward AskUserQuestion to iOS
        hookEventHandler.onForwardAskUserQuestionToiOS = { [weak self] askInfo in
            guard let self else { return }
            Task {
                await self.connectionManager.forwardAskUserQuestion(askInfo)
                await self.connectionManager.broadcastSessionList()
            }
        }
        // Dismiss AskUserQuestion card on iOS when answered on Mac
        hookEventHandler.onAskUserQuestionDismissed = { [weak self] sessionId, ptySessionId in
            guard let self else { return }
            Task {
                await self.connectionManager.forwardAskUserQuestionDismiss(sessionId: sessionId, ptySessionId: ptySessionId)
                await self.connectionManager.broadcastSessionList()
            }
        }

        hookEventHandler.onPromptDismissed = { [weak self] sessionId, ptySessionId in
            guard let self else { return }
            self.promptPanelController.dismissPrompt(for: sessionId)
            Task {
                let resolvedPty: String
                if let pty = ptySessionId {
                    resolvedPty = pty
                } else {
                    resolvedPty = await self.resolvePTYSessionId(claudeSessionId: sessionId, cwd: nil)
                }
                await self.connectionManager.forwardHookDismiss(sessionId: sessionId, ptySessionId: resolvedPty)
                await self.connectionManager.broadcastSessionList()
            }
        }

        // Wire idle prompt callbacks
        hookEventHandler.onIdlePromptReceived = { [weak self] info in
            guard let self else { return }

            // Resolve PTY session ID via direct value or fallback chain
            Task {
                let ptyId = await self.resolvePTYSessionId(
                    claudeSessionId: info.sessionId,
                    cwd: info.cwd,
                    ptySessionId: info.ptySessionId
                )
                self.idlePromptPTYMapping[info.sessionId] = ptyId
                self.hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: info.sessionId)

                self.playSound(.done)
                if PreferencesManager.shared.showDonePanel {
                    if let detected = info.detectedOptions {
                        self.promptPanelController.showMultiOptionPrompt(info, options: detected.options)
                    } else {
                        self.promptPanelController.showIdlePrompt(info)
                    }
                }
            }
        }
        hookEventHandler.onForwardIdleToiOS = { [weak self] info in
            guard let self else { return }
            Task {
                let ptyId = await self.resolvePTYSessionId(
                    claudeSessionId: info.sessionId,
                    cwd: info.cwd,
                    ptySessionId: info.ptySessionId
                )
                await self.connectionManager.forwardIdlePrompt(info, resolvedPTYSessionId: ptyId)
                await self.connectionManager.broadcastSessionList()
            }
        }
        hookEventHandler.onIdlePromptDismissed = { [weak self] sessionId, ptySessionId in
            guard let self else { return }
            self.idlePromptPTYMapping.removeValue(forKey: sessionId)
            self.promptPanelController.dismissPrompt(for: sessionId)
            Task {
                let resolvedPty: String
                if let pty = ptySessionId {
                    resolvedPty = pty
                } else {
                    resolvedPty = await self.resolvePTYSessionId(claudeSessionId: sessionId, cwd: nil)
                }
                await self.connectionManager.forwardIdlePromptDismiss(sessionId: sessionId, ptySessionId: resolvedPty)
                await self.connectionManager.broadcastSessionList()
            }
        }

        // Wire focus button to activate the terminal/IDE
        promptPanelController.onFocus = { [weak self] sessionId in
            self?.focusSession(sessionId)
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

        // Wire multi-option "Other" response: navigate to Other option, activate it, type text
        promptPanelController.onMultiOptionOtherResponse = { [weak self] sessionId, arrowSequence, text in
            guard let self else { return }
            Task {
                let ptySessionId = self.resolveIdlePromptPTYSessionId(sessionId)

                // Send arrow keys to navigate to "Other" + Enter to activate text input
                if let navData = arrowSequence.data(using: .utf8) {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: navData)
                }
                // Wait for the TUI to switch to text input mode
                try? await Task.sleep(for: .milliseconds(100))

                // Type the text
                if let textData = text.data(using: .utf8) {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: textData)
                }
                // Brief delay before submitting
                try? await Task.sleep(for: .milliseconds(50))

                // Press Enter to submit
                if let enterData = Data([0x0D]) as Data? {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: enterData)
                }
                self.hookEventHandler.dismissIdlePrompt(for: sessionId)
            }
        }

        // Wire AskUserQuestion completion: send answers through hook response via updatedInput
        promptPanelController.onAskUserQuestionSubmit = { [weak self] sessionId, info, answers in
            guard let self else { return }
            Task {
                // Build updatedInput: original toolInput + answers dict
                var updatedInput: [String: Any] = info.toolInput?.mapValues { $0.value } ?? [:]
                updatedInput["answers"] = answers

                // Send approval with the answers included in the response
                await self.hookListener.sendPermissionResponse(
                    sessionId: sessionId,
                    decision: "allow",
                    updatedInput: updatedInput
                )
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

        // Wire away detector to connection manager signals
        awayDetector.bleRSSIProvider = { [weak self] in
            self?.connectionManager.latestBLERSSI
        }
        awayDetector.networkPresenceProvider = { [weak self] in
            !(self?.connectionManager.connectedDevices.isEmpty ?? true)
        }
        awayDetector.startDetecting()

        // Periodically refresh session message counts
        startSessionRefreshTimer()

        // Restart timer when session refresh interval changes
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let currentInterval = self.sessionRefreshTimer?.timeInterval ?? 0
            let newInterval = TimeInterval(PreferencesManager.shared.sessionRefreshInterval)
            if currentInterval != newInterval {
                self.startSessionRefreshTimer()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("BalconyMac terminating")
        awayDetector.stopDetecting()
        sessionRefreshTimer?.invalidate()
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = setupObserver {
            NotificationCenter.default.removeObserver(observer)
        }

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

        // Update UI model with enriched session data
        await refreshSessionList()

        // Forward to connected iOS clients
        await connectionManager.forwardSessionEvent(event)
    }

    /// Refresh session list with message counts from JSONL files.
    @MainActor
    private func refreshSessionList() async {
        var sessions = await ptySessionManager.getActiveSessions()
        for i in sessions.indices {
            let count = await sessionFileReader.countMessages(projectPath: sessions[i].projectPath)
            sessions[i].messageCount = count
        }
        sessionListModel.sessions = sessions
    }

    /// Start a timer that periodically refreshes session message counts.
    private func startSessionRefreshTimer() {
        sessionRefreshTimer?.invalidate()
        let interval = TimeInterval(PreferencesManager.shared.sessionRefreshInterval)
        sessionRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshSessionList()
            }
        }
    }

    // MARK: - AskUserQuestion Response (from iOS)

    /// Handle an AskUserQuestion response received from iOS.
    @MainActor
    func handleAskUserQuestionResponse(sessionId: String, answers: [String: String]) async {
        guard let askInfo = hookEventHandler.pendingAskUserQuestion(for: sessionId) else {
            logger.debug("Ignoring stale AskUserQuestion response for session \(sessionId)")
            return
        }

        // Build updatedInput: original toolInput + answers dict
        var updatedInput: [String: Any] = askInfo.toolInput?.mapValues { $0.value } ?? [:]
        updatedInput["answers"] = answers

        // Send approval with the answers included in the response
        await hookListener.sendPermissionResponse(
            sessionId: sessionId,
            decision: "allow",
            updatedInput: updatedInput
        )
        hookEventHandler.dismissPrompt(for: sessionId)
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
