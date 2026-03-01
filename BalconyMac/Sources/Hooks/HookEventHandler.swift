import Foundation
import BalconyShared
import os

// MARK: - Prompt Lifecycle

/// State of a permission prompt through its lifecycle.
enum PromptLifecycleState {
    /// Hook received, panel shown, awaiting PTY confirmation or response.
    case active(PermissionPromptInfo)

    /// Prompt was answered (transitional — clears to idle or next in queue).
    case answered

    var info: PermissionPromptInfo? {
        if case .active(let info) = self { return info }
        return nil
    }
}

/// Per-session prompt tracking with a FIFO queue.
struct SessionPromptQueue {
    /// The currently active prompt (shown on Mac panel and forwarded to iOS).
    var state: PromptLifecycleState?

    /// Queued prompts waiting to be shown after the current one is answered.
    var queue: [PermissionPromptInfo] = []

    /// Bytes of PTY output received since the current prompt became active.
    var outputSincePrompt: Int = 0

    var activeInfo: PermissionPromptInfo? { state?.info }
    var isIdle: Bool { state == nil }
}

// MARK: - HookEventHandler

/// Processes hook events from Claude Code, manages prompt lifecycle
/// with queuing and timing coordination, and notifies all surfaces.
@MainActor
final class HookEventHandler: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "HookEventHandler")

    /// Per-session prompt state and queue.
    private var sessionQueues: [String: SessionPromptQueue] = [:]

    /// Published snapshot of active prompts for any observers.
    @Published private(set) var pendingPrompts: [String: PermissionPromptInfo] = [:]

    /// Buffered Stop event data per session (correlates with Notification).
    private var lastStopData: [String: (message: String, cwd: String?, ptySessionId: String?)] = [:]

    /// Buffered Notification(idle_prompt) events waiting for a Stop to correlate with.
    /// When Notification arrives before Stop, we store the cwd and ptySessionId here.
    private var pendingIdleNotifications: [String: (cwd: String?, ptySessionId: String?)] = [:]

    /// Active idle prompts per session (Claude waiting for user input).
    @Published private(set) var pendingIdlePrompts: [String: IdlePromptInfo] = [:]

    /// Mapping from PTY session IDs to Claude Code session IDs.
    /// One PTY session can host multiple Claude Code sessions.
    private var ptyToClaudeSessionIds: [String: Set<String>] = [:]

    // MARK: - Callbacks

    /// Called when a new permission prompt should be shown on Mac.
    var onPromptReceived: ((PermissionPromptInfo) -> Void)?

    /// Called when a prompt is dismissed (answered from any surface).
    var onPromptDismissed: ((String) -> Void)?

    /// Called to forward hook events to iOS via WebSocket.
    var onForwardToiOS: ((PermissionPromptInfo) -> Void)?

    /// Called when Claude stops and waits for user input (idle prompt).
    var onIdlePromptReceived: ((IdlePromptInfo) -> Void)?

    /// Called when an idle prompt is dismissed (user started typing).
    var onIdlePromptDismissed: ((String) -> Void)?

    /// Called to forward idle prompt events to iOS via WebSocket.
    var onForwardIdleToiOS: ((IdlePromptInfo) -> Void)?

    /// Called when an AskUserQuestion tool is detected (rich multi-option prompt).
    var onAskUserQuestionReceived: ((AskUserQuestionInfo) -> Void)?

    // MARK: - Configuration

    /// Threshold of new PTY output bytes that indicates the prompt was answered
    /// and Claude Code has moved on to producing new output.
    private static let dismissOutputThreshold = 200

    // MARK: - PTY Session Mapping

    /// Register a mapping from PTY session ID to Claude Code session ID.
    /// Called by AppDelegate after resolving the PTY session for a hook event.
    func registerPTYMapping(ptySessionId: String, claudeSessionId: String) {
        ptyToClaudeSessionIds[ptySessionId, default: []].insert(claudeSessionId)
    }

    // MARK: - Event Processing

    /// Handle a raw hook event from HookListener.
    func handleHookEvent(_ event: HookEvent) {
        logger.info("Hook event: \(event.hookEventName) session=\(event.sessionId)")

        switch event.hookEventName {
        case "PermissionRequest":
            handlePermissionRequest(event)
        case "PreToolUse":
            handlePreToolUse(event)
        case "Stop":
            handleStop(event)
        case "Notification":
            handleNotification(event)
        default:
            logger.debug("Ignoring hook event: \(event.hookEventName)")
        }
    }

    private func handlePreToolUse(_ event: HookEvent) {
        // Claude is actively working (user must have responded) — dismiss any idle prompt
        lastStopData.removeValue(forKey: event.sessionId)
        dismissIdlePrompt(for: event.sessionId)
    }

    private func handlePermissionRequest(_ event: HookEvent) {
        guard let promptInfo = PermissionPromptInfo.from(event) else {
            logger.warning("Could not parse PermissionPromptInfo from hook event")
            return
        }

        // A permission request means Claude is working, not idle
        // Clear any buffered Stop data (cancels the timer-based idle detection)
        lastStopData.removeValue(forKey: event.sessionId)
        // Dismiss any active idle prompt
        dismissIdlePrompt(for: event.sessionId)

        logger.info("Permission prompt: \(promptInfo.toolName) risk=\(promptInfo.riskLevel.rawValue) session=\(promptInfo.sessionId)")

        let sessionId = promptInfo.sessionId
        var sq = sessionQueues[sessionId] ?? SessionPromptQueue()

        if sq.isIdle {
            // Check for AskUserQuestion — route to rich panel instead of Deny/Always/Allow
            if let askInfo = AskUserQuestionInfo.from(event) {
                logger.info("Detected AskUserQuestion with \(askInfo.questions.count) question(s) for session \(sessionId)")
                // Track as active permission prompt for lifecycle management
                sq.state = .active(promptInfo)
                sq.outputSincePrompt = 0
                sessionQueues[sessionId] = sq
                pendingPrompts[sessionId] = promptInfo
                onAskUserQuestionReceived?(askInfo)
                return
            }

            activatePrompt(promptInfo, in: &sq)
            sessionQueues[sessionId] = sq
        } else {
            sq.queue.append(promptInfo)
            sessionQueues[sessionId] = sq
            logger.info("Queued prompt for session \(sessionId) — queue depth: \(sq.queue.count)")
        }
    }

    private func handleStop(_ event: HookEvent) {
        guard let message = event.lastAssistantMessage, !message.isEmpty else { return }

        let sessionId = event.sessionId
        logger.debug("Stop: session=\(sessionId) msg=\(message.prefix(80))...")

        let ptySessionId = event.balconyPtySessionId

        // Don't emit if a permission prompt is active (Claude is working, not idle)
        guard sessionQueues[sessionId]?.isIdle ?? true else {
            // Buffer in case a Notification arrives later
            lastStopData[sessionId] = (message: message, cwd: event.cwd, ptySessionId: ptySessionId)
            return
        }

        // Consume any pending Notification (arrived before this Stop)
        let notifData = pendingIdleNotifications.removeValue(forKey: sessionId)

        // Emit immediately. If a PermissionRequest follows, it will dismiss the idle prompt.
        logger.info("Idle prompt for session \(sessionId)")
        emitIdlePrompt(
            sessionId: sessionId,
            message: message,
            cwd: event.cwd ?? notifData?.cwd,
            ptySessionId: ptySessionId ?? notifData?.ptySessionId
        )
    }

    private func handleNotification(_ event: HookEvent) {
        guard event.notificationType == "idle_prompt" else {
            logger.debug("Ignoring notification type: \(event.notificationType ?? "nil")")
            return
        }

        let sessionId = event.sessionId

        // Don't show idle prompt if a permission prompt is active
        guard sessionQueues[sessionId]?.isIdle ?? true else { return }

        // If an idle prompt is already showing, skip
        guard pendingIdlePrompts[sessionId] == nil else { return }

        // Try to correlate with a buffered Stop message (buffered when permission prompt was active)
        if let stopData = lastStopData.removeValue(forKey: sessionId) {
            emitIdlePrompt(sessionId: sessionId, message: stopData.message, cwd: stopData.cwd ?? event.cwd, ptySessionId: stopData.ptySessionId ?? event.balconyPtySessionId)
        } else {
            // Stop hasn't arrived yet — buffer this Notification and wait
            pendingIdleNotifications[sessionId] = (cwd: event.cwd, ptySessionId: event.balconyPtySessionId)
            logger.debug("Buffered idle Notification for session \(sessionId) — waiting for Stop")

            // Clean up if Stop never arrives
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.pendingIdleNotifications.removeValue(forKey: sessionId)
            }
        }
    }

    // MARK: - Idle Prompt Emission

    /// Create and emit an idle prompt once both Stop and Notification have been correlated.
    private func emitIdlePrompt(sessionId: String, message: String, cwd: String?, ptySessionId: String? = nil) {
        let info = IdlePromptInfo(sessionId: sessionId, lastAssistantMessage: message, cwd: cwd, ptySessionId: ptySessionId)
        pendingIdlePrompts[sessionId] = info

        logger.info("Idle prompt for session \(sessionId): \(message.prefix(80))...")

        onIdlePromptReceived?(info)
        onForwardIdleToiOS?(info)
    }

    // MARK: - PTY Output Monitoring

    /// Called from the PTY output callback. The sessionId here is the PTY session ID,
    /// which we resolve to the Claude Code session ID for prompt lookup.
    func handlePTYOutput(ptySessionId: String, byteCount: Int) {
        // Resolve PTY session ID to Claude Code session IDs
        guard let claudeSessionIds = ptyToClaudeSessionIds[ptySessionId] else { return }

        // Note: we do NOT auto-dismiss idle prompts on PTY output.
        // Claude Code's terminal produces output even when idle (cursor, prompt, status line).
        // Idle prompts are dismissed by: user response, new Stop, PermissionRequest, or session end.

        for claudeSessionId in claudeSessionIds {
            guard var sq = sessionQueues[claudeSessionId], sq.activeInfo != nil else { continue }

            sq.outputSincePrompt += byteCount
            sessionQueues[claudeSessionId] = sq

            if sq.outputSincePrompt >= Self.dismissOutputThreshold {
                logger.info("Auto-dismissing prompt for session \(claudeSessionId) — \(sq.outputSincePrompt) bytes of new output")
                dismissPrompt(for: claudeSessionId)
            }
        }
    }

    // MARK: - Dismissal

    /// Dismiss the active prompt for a session. If queued prompts exist,
    /// the next one is activated immediately.
    func dismissPrompt(for sessionId: String) {
        guard var sq = sessionQueues[sessionId], !sq.isIdle else { return }

        // Transition current prompt to answered
        sq.state = .answered
        sq.outputSincePrompt = 0

        pendingPrompts.removeValue(forKey: sessionId)
        logger.info("Prompt dismissed for session: \(sessionId)")
        onPromptDismissed?(sessionId)

        // Check queue for next prompt
        if !sq.queue.isEmpty {
            let next = sq.queue.removeFirst()
            activatePrompt(next, in: &sq)
            sessionQueues[sessionId] = sq
            logger.info("Showing next queued prompt for session \(sessionId) — remaining: \(sq.queue.count)")
        } else {
            sq.state = nil
            sessionQueues[sessionId] = sq
        }
    }

    // MARK: - Stdin Activity

    /// Called when the user types in the local terminal. Resolves the PTY session ID
    /// to the Claude session ID and dismisses any pending idle prompt.
    func handleStdinActivity(ptySessionId: String) {
        guard let claudeSessionIds = ptyToClaudeSessionIds[ptySessionId] else { return }
        for claudeSessionId in claudeSessionIds {
            guard pendingIdlePrompts[claudeSessionId] != nil else { continue }
            logger.info("Stdin activity detected for PTY \(ptySessionId) → dismissing idle prompt for \(claudeSessionId)")
            dismissIdlePrompt(for: claudeSessionId)
        }
    }

    // MARK: - Idle Prompt Dismissal

    /// Dismiss the idle prompt for a session (user started typing or new output arrived).
    func dismissIdlePrompt(for sessionId: String) {
        guard pendingIdlePrompts.removeValue(forKey: sessionId) != nil else { return }
        logger.info("Idle prompt dismissed for session: \(sessionId)")
        onIdlePromptDismissed?(sessionId)
    }

    // MARK: - Queries

    /// Check if a session has an active prompt.
    func hasPendingPrompt(for sessionId: String) -> Bool {
        sessionQueues[sessionId]?.activeInfo != nil
    }

    /// Get the current active prompt info (e.g., for resending to a reconnecting iOS client).
    func pendingPrompt(for sessionId: String) -> PermissionPromptInfo? {
        sessionQueues[sessionId]?.activeInfo
    }

    /// Get the current idle prompt info (e.g., for resending to a reconnecting iOS client).
    func pendingIdlePrompt(for sessionId: String) -> IdlePromptInfo? {
        pendingIdlePrompts[sessionId]
    }

    // MARK: - Session Lifecycle

    /// Clear all prompt state for a session that has ended.
    func sessionEnded(_ sessionId: String) {
        if sessionQueues.removeValue(forKey: sessionId) != nil {
            pendingPrompts.removeValue(forKey: sessionId)
            logger.debug("Cleared prompt state for ended session: \(sessionId)")
        }
        pendingIdlePrompts.removeValue(forKey: sessionId)
        lastStopData.removeValue(forKey: sessionId)
        pendingIdleNotifications.removeValue(forKey: sessionId)
    }

    // MARK: - Private

    /// Activate a prompt: set state, update published snapshot, and notify all surfaces.
    private func activatePrompt(_ info: PermissionPromptInfo, in sq: inout SessionPromptQueue) {
        let sessionId = info.sessionId

        sq.state = .active(info)
        sq.outputSincePrompt = 0

        pendingPrompts[sessionId] = info

        // Notify Mac panel
        onPromptReceived?(info)

        // Forward to iOS
        onForwardToiOS?(info)
    }
}
