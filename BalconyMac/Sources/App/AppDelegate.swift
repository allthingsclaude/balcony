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
    let voiceTranscriber = VoiceTranscriber()
    let setupWindowController = OnboardingWindowController()

    /// Pre-resolved PTY session IDs for idle prompts (Claude session ID → PTY session ID).
    /// Stored when the idle prompt is shown so text responses route to the correct PTY
    /// even after the idle prompt info (with cwd) has been dismissed.
    private var idlePromptPTYMapping: [String: String] = [:]

    /// Cached file descriptors for PTY sessions (PTY session ID → fd).
    /// Used for direct (nonisolated) writes that bypass the PTYSessionManager actor,
    /// avoiding contention with read operations during live typing.
    private var cachedSessionFDs: [String: Int32] = [:]

    /// Timer that periodically refreshes session message counts.
    private var sessionRefreshTimer: Timer?

    /// Observation token for UserDefaults changes.
    private var defaultsObserver: NSObjectProtocol?

    /// Observation token for re-run setup wizard requests.
    private var setupObserver: NSObjectProtocol?

    /// Whether services have been started.
    private var servicesStarted = false

    /// Global and local monitors for double-Cmd hotkey.
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    /// Timestamp of the last Cmd key release (for double-tap detection).
    private var lastCmdRelease: TimeInterval = 0

    /// Timer that fires after a short hold to start voice recording (tap-then-hold detection).
    private var voiceHoldTimer: Timer?

    /// Whether voice recording is currently active via Cmd hold.
    private var isVoiceRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")

        PreferencesManager.shared.applyAppearance()

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

    // MARK: - Global Hotkey (Double-Cmd)

    private func startHotkeyMonitor() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handleHotkeyEvent(event)
        }

        // Global monitor fires when another app is active
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)

        // Local monitor fires when Balcony itself is active
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event
        }
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        let cmdPressed = event.modifierFlags.contains(.command)
        let onlyCmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command

        if cmdPressed && onlyCmd {
            // Cmd pressed alone — check if this is the second press (voice trigger candidate)
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - lastCmdRelease

            if elapsed < 0.35 && elapsed > 0 && promptPanelController.hasPanels
                && PreferencesManager.shared.voiceInputEnabled && voiceTranscriber.isAvailable {
                // Second press within double-tap window with voice enabled.
                // Start a hold timer — if held long enough, start voice recording.
                // If released quickly, it's a normal double-tap (focus panel).
                voiceHoldTimer?.invalidate()
                voiceHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    self?.startVoiceInput()
                }
                // Clear to prevent double-tap detection on release
                lastCmdRelease = 0
            }
            return
        }

        if !cmdPressed {
            // A modifier was released. Check if Cmd was just released (no other modifiers held).
            let remaining = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard remaining.isEmpty else { return }

            // Voice recording active — stop and send on Cmd release
            if isVoiceRecording {
                stopVoiceInput()
                lastCmdRelease = 0
                return
            }

            // Hold timer was running but didn't fire — quick tap-tap → focus panel
            if voiceHoldTimer != nil {
                voiceHoldTimer?.invalidate()
                voiceHoldTimer = nil
                lastCmdRelease = 0
                if promptPanelController.hasPanels {
                    promptPanelController.activateFrontmostPanel()
                }
                return
            }

            // Normal Cmd release — record timestamp and check for double-tap
            // (used when voice is disabled, so double-tap still focuses panel)
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - self.lastCmdRelease
            self.lastCmdRelease = now

            if elapsed < 0.35 {
                self.lastCmdRelease = 0
                let hasPanels = self.promptPanelController.hasPanels
                if hasPanels {
                    self.promptPanelController.activateFrontmostPanel()
                }
            }
        }
    }

    // MARK: - Voice Input

    private func startVoiceInput() {
        voiceHoldTimer = nil
        guard promptPanelController.hasPanels else { return }

        isVoiceRecording = true
        SoundEffect.shared.playDing()
        voiceTranscriber.startRecording()

        // Activate the panel so the recording UI is visible
        promptPanelController.activateFrontmostPanel()
        logger.info("Voice input started")
    }

    private func stopVoiceInput() {
        isVoiceRecording = false
        SoundEffect.shared.playDong()
        let transcript = voiceTranscriber.stopRecording()
        logger.info("Voice input stopped, transcript: '\(transcript.prefix(80))'")

        guard !transcript.isEmpty else { return }
        guard let sessionId = promptPanelController.frontmostSessionId else { return }

        let ptySessionId = resolveIdlePromptPTYSessionId(sessionId)

        // Send transcript text to PTY
        if let data = transcript.data(using: .utf8) {
            if let fd = cachedSessionFDs[ptySessionId] {
                PTYSessionManager.sendInputDirect(fd: fd, data: data)
            } else {
                Task { await ptySessionManager.sendInput(sessionId: ptySessionId, data: data) }
            }
        }

        // Send Enter
        if let fd = cachedSessionFDs[ptySessionId] {
            PTYSessionManager.sendInputDirect(fd: fd, data: Data([0x0D]))
        } else {
            Task { await ptySessionManager.sendInput(sessionId: ptySessionId, data: Data([0x0D])) }
        }

        // Dismiss the idle prompt
        hookEventHandler.dismissIdlePrompt(for: sessionId)
    }

    private func stopHotkeyMonitor() {
        if let monitor = globalHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalHotkeyMonitor = nil
        }
        if let monitor = localHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            localHotkeyMonitor = nil
        }
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
        PreferencesManager.playBundledSound(soundName)
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

        // Wire voice transcriber to prompt panel controller
        promptPanelController.voiceTranscriber = voiceTranscriber
        voiceTranscriber.checkAuthorization()
        if PreferencesManager.shared.voiceInputEnabled {
            voiceTranscriber.requestAuthorization()
        }

        // Wire hook event handler callbacks
        hookEventHandler.onPromptReceived = { [weak self] promptInfo in
            guard let self else { return }
            // Eagerly resolve and register the PTY↔Claude session mapping
            Task {
                _ = await self.resolvePTYSessionId(claudeSessionId: promptInfo.sessionId, cwd: promptInfo.cwd, ptySessionId: promptInfo.ptySessionId, hookPeerPID: promptInfo.hookPeerPID)
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
                    ptySessionId: promptInfo.ptySessionId,
                    hookPeerPID: promptInfo.hookPeerPID
                )
                await self.connectionManager.forwardHookEvent(promptInfo, resolvedPTYSessionId: ptyId)
                await self.connectionManager.broadcastSessionList()
            }
        }
        // Wire AskUserQuestion: show rich panel with actual question and options
        hookEventHandler.onAskUserQuestionReceived = { [weak self] askInfo in
            guard let self else { return }
            // Eagerly resolve and register the PTY↔Claude session mapping
            Task {
                _ = await self.resolvePTYSessionId(claudeSessionId: askInfo.sessionId, cwd: askInfo.cwd, ptySessionId: askInfo.ptySessionId, hookPeerPID: askInfo.hookPeerPID)
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

            self.logger.info("[IDLE] Received idle prompt: session=\(info.sessionId) cwd=\(info.cwd ?? "nil") ptySessionId=\(info.ptySessionId ?? "nil") hookPeerPID=\(info.hookPeerPID.map(String.init) ?? "nil")")

            // Resolve PTY session ID via direct value or fallback chain
            Task {
                let ptyId = await self.resolvePTYSessionId(
                    claudeSessionId: info.sessionId,
                    cwd: info.cwd,
                    ptySessionId: info.ptySessionId,
                    hookPeerPID: info.hookPeerPID
                )
                self.logger.info("[IDLE] Stored mapping: \(info.sessionId) → \(ptyId)")
                self.idlePromptPTYMapping[info.sessionId] = ptyId
                self.hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: info.sessionId)

                // Show panel BEFORE caching fd — the fdForSession await can stall
                // on actor contention and must not block panel display.
                self.playSound(.done)
                if PreferencesManager.shared.showDonePanel {
                    if let detected = info.detectedOptions {
                        self.promptPanelController.showMultiOptionPrompt(info, options: detected.options)
                    } else {
                        self.promptPanelController.showIdlePrompt(info)
                    }
                }

                // Cache the socket fd for direct (non-actor) writes during live typing
                if let fd = await self.ptySessionManager.fdForSession(ptyId) {
                    self.cachedSessionFDs[ptyId] = fd
                }
            }
        }
        hookEventHandler.onForwardIdleToiOS = { [weak self] info in
            guard let self else { return }
            Task {
                let ptyId = await self.resolvePTYSessionId(
                    claudeSessionId: info.sessionId,
                    cwd: info.cwd,
                    ptySessionId: info.ptySessionId,
                    hookPeerPID: info.hookPeerPID
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

        // Wire live typing from idle prompt panel to PTY input.
        // Uses direct (nonisolated) socket write to bypass actor contention —
        // the PTYSessionManager actor may be busy processing read events.
        promptPanelController.onTyping = { [weak self] sessionId, keystroke in
            guard let self else { return }
            let ptySessionId = self.resolveIdlePromptPTYSessionId(sessionId)
            guard let data = keystroke.data(using: .utf8) else { return }

            // Try direct write using cached fd (no actor await)
            if let fd = self.cachedSessionFDs[ptySessionId] {
                PTYSessionManager.sendInputDirect(fd: fd, data: data)
            } else {
                // Fallback: go through the actor (may be delayed by contention)
                Task {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: data)
                }
            }
        }

        // Wire idle prompt panel text submission — just send Enter (text already sent via live typing)
        promptPanelController.onTextResponse = { [weak self] sessionId, _ in
            guard let self else { return }
            let ptySessionId = self.resolveIdlePromptPTYSessionId(sessionId)
            self.logger.info("Submit (Enter): claude=\(sessionId) → pty=\(ptySessionId)")

            // Send Enter via direct write to avoid actor contention
            if let fd = self.cachedSessionFDs[ptySessionId] {
                PTYSessionManager.sendInputDirect(fd: fd, data: Data([0x0D]))
            } else {
                Task {
                    await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: Data([0x0D]))
                }
            }
            self.hookEventHandler.dismissIdlePrompt(for: sessionId)
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
            let ptySessionId = self.resolveIdlePromptPTYSessionId(sessionId)

            if let data = sequence.data(using: .utf8) {
                if let fd = self.cachedSessionFDs[ptySessionId] {
                    PTYSessionManager.sendInputDirect(fd: fd, data: data)
                } else {
                    Task { await self.ptySessionManager.sendInput(sessionId: ptySessionId, data: data) }
                }
            }
            self.hookEventHandler.dismissIdlePrompt(for: sessionId)
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
            // (but not within 1s of restoring focus — app switching generates spurious stdin)
            await ptySessionManager.setOnStdinActivity { [weak self] ptySessionId in
                Task { @MainActor in
                    guard let self else { return }
                    let elapsed = ProcessInfo.processInfo.systemUptime - self.promptPanelController.lastRestoreTime
                    if elapsed < 1.0 { return }
                    self.hookEventHandler.handleStdinActivity(ptySessionId: ptySessionId)
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

        // Start global hotkey monitor (double-Cmd to focus panel)
        startHotkeyMonitor()

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
            // Request speech authorization when voice input is enabled
            if PreferencesManager.shared.voiceInputEnabled && !self.voiceTranscriber.isAvailable {
                self.voiceTranscriber.requestAuthorization()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("BalconyMac terminating")
        if isVoiceRecording { voiceTranscriber.stopRecording() }
        voiceHoldTimer?.invalidate()
        stopHotkeyMonitor()
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
    private func resolvePTYSessionId(claudeSessionId: String, cwd: String?, ptySessionId: String? = nil, hookPeerPID: Int32? = nil) async -> String {
        // Check if already mapped (e.g., from a previous idle prompt)
        if let existing = hookEventHandler.ptySessionId(for: claudeSessionId) {
            logger.info("[RESOLVE] claude=\(claudeSessionId) → existing mapping: \(existing)")
            return existing
        }
        // Best: direct PTY session ID from BalconyCLI wrapper
        if let ptyId = ptySessionId {
            logger.info("[RESOLVE] claude=\(claudeSessionId) → direct ptySessionId: \(ptyId)")
            hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: claudeSessionId)
            return ptyId
        }
        // Walk the hook handler's process tree to find a registered PTY session PID.
        // hook-handler → python3 → bash → claude → (BalconyCLI if wrapped)
        // The PTY session stores the Claude process PID, so we walk up until we find a match.
        if let peerPID = hookPeerPID {
            logger.info("[RESOLVE] claude=\(claudeSessionId) → trying PID walk from hookPeerPID=\(peerPID)")
            if let ptyId = await findPTYSessionByProcessTree(hookPID: peerPID) {
                logger.info("[RESOLVE] claude=\(claudeSessionId) → PID walk found: \(ptyId)")
                hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: claudeSessionId)
                return ptyId
            }
            logger.info("[RESOLVE] claude=\(claudeSessionId) → PID walk failed")
        } else {
            logger.info("[RESOLVE] claude=\(claudeSessionId) → hookPeerPID is nil")
        }
        // Fallback: match by working directory, excluding PTY sessions
        // already mapped to other Claude sessions
        let alreadyMapped = hookEventHandler.mappedPTYSessionIds
        if let cwd, let ptyId = await ptySessionManager.findSessionIdByCwd(cwd, excluding: alreadyMapped) {
            logger.info("[RESOLVE] claude=\(claudeSessionId) → cwd match: \(ptyId) (cwd=\(cwd))")
            hookEventHandler.registerPTYMapping(ptySessionId: ptyId, claudeSessionId: claudeSessionId)
            return ptyId
        }
        // Fallback: if only one PTY session exists, use it
        let sessions = await ptySessionManager.getActiveSessions()
        if sessions.count == 1, let only = sessions.first {
            logger.info("[RESOLVE] claude=\(claudeSessionId) → single session fallback: \(only.id)")
            hookEventHandler.registerPTYMapping(ptySessionId: only.id, claudeSessionId: claudeSessionId)
            return only.id
        }
        // Last resort: return the Claude session ID as-is
        logger.warning("[RESOLVE] claude=\(claudeSessionId) → FAILED (no PTY match, \(sessions.count) active sessions)")
        return claudeSessionId
    }

    /// Walk the process tree from a hook handler PID upward to find a registered PTY session.
    private func findPTYSessionByProcessTree(hookPID: Int32) async -> String? {
        var current = hookPID
        for _ in 0..<20 {
            // Check if this PID matches any registered PTY session
            if let sessionId = await ptySessionManager.findSessionIdByPID(current) {
                return sessionId
            }
            let parent = Self.parentPID(of: current)
            if parent <= 1 || parent == current { break }
            current = parent
        }
        return nil
    }

    // MARK: - Idle Prompt PTY Resolution

    /// Resolve the PTY session ID for an idle prompt response, using the cached mapping first.
    private func resolveIdlePromptPTYSessionId(_ sessionId: String) -> String {
        // Check the pre-resolved mapping first (non-destructive read)
        if let cached = idlePromptPTYMapping[sessionId] {
            return cached
        }
        // Fallback: try reverse lookup from hookEventHandler
        if let ptyId = hookEventHandler.ptySessionId(for: sessionId) {
            return ptyId
        }
        logger.warning("No PTY mapping for idle session \(sessionId), using raw ID")
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

        // Prune stale sessions whose process is no longer running
        var staleIds: [String] = []
        for session in sessions {
            if let pid = await ptySessionManager.pid(for: session.id), pid > 0 {
                if !Self.isProcessAlive(pid) {
                    staleIds.append(session.id)
                }
            }
        }
        for staleId in staleIds {
            logger.info("Pruning stale session (process dead): \(staleId)")
            await ptySessionManager.removeSession(staleId)
            hookEventHandler.sessionEnded(staleId)
        }
        if !staleIds.isEmpty {
            sessions = await ptySessionManager.getActiveSessions()
        }

        for i in sessions.indices {
            // Look up the Claude session ID for this PTY session to count from the right file
            let claudeIds = hookEventHandler.claudeSessionIds(for: sessions[i].id)
            let count = await sessionFileReader.countMessages(
                projectPath: sessions[i].projectPath,
                claudeSessionId: claudeIds.first
            )
            sessions[i].messageCount = count

            // Enrich with attention/idle state
            sessions[i].needsAttention = hookEventHandler.hasAttentionNeeded(forPTYSession: sessions[i].id)
            sessions[i].awaitingInput = hookEventHandler.hasIdlePrompt(forPTYSession: sessions[i].id)
        }
        sessionListModel.sessions = sessions
    }

    /// Check if a process with the given PID is still running.
    private static func isProcessAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
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
