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
    /// Stores (message, cwd) from the Stop event.
    private var lastStopData: [String: (message: String, cwd: String?)] = [:]

    /// Active idle prompts per session (Claude waiting for user input).
    @Published private(set) var pendingIdlePrompts: [String: IdlePromptInfo] = [:]

    /// Mapping from PTY session IDs to Claude Code session IDs.
    /// Populated when hook events arrive (using cwd to find the matching PTY session).
    private var ptyToClaudeSessionId: [String: String] = [:]

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

    // MARK: - Configuration

    /// Threshold of new PTY output bytes that indicates the prompt was answered
    /// and Claude Code has moved on to producing new output.
    private static let dismissOutputThreshold = 200

    // MARK: - PTY Session Mapping

    /// Register a mapping from PTY session ID to Claude Code session ID.
    /// Called by AppDelegate after resolving the PTY session for a hook event.
    func registerPTYMapping(ptySessionId: String, claudeSessionId: String) {
        ptyToClaudeSessionId[ptySessionId] = claudeSessionId
    }

    // MARK: - Event Processing

    /// Handle a raw hook event from HookListener.
    func handleHookEvent(_ event: HookEvent) {
        switch event.hookEventName {
        case "PermissionRequest":
            handlePermissionRequest(event)
        case "Stop":
            handleStop(event)
        case "Notification":
            handleNotification(event)
        default:
            logger.debug("Ignoring hook event: \(event.hookEventName)")
        }
    }

    private func handlePermissionRequest(_ event: HookEvent) {
        guard let promptInfo = PermissionPromptInfo.from(event) else {
            logger.warning("Could not parse PermissionPromptInfo from hook event")
            return
        }

        // A permission request means Claude is working, not idle — dismiss any idle prompt
        dismissIdlePrompt(for: event.sessionId)

        logger.info("Permission prompt: \(promptInfo.toolName) risk=\(promptInfo.riskLevel.rawValue) session=\(promptInfo.sessionId)")

        let sessionId = promptInfo.sessionId
        var sq = sessionQueues[sessionId] ?? SessionPromptQueue()

        if sq.isIdle {
            activatePrompt(promptInfo, in: &sq)
            sessionQueues[sessionId] = sq
        } else {
            sq.queue.append(promptInfo)
            sessionQueues[sessionId] = sq
            logger.info("Queued prompt for session \(sessionId) — queue depth: \(sq.queue.count)")
        }
    }

    private func handleStop(_ event: HookEvent) {
        // Buffer the last assistant message + cwd — Notification(idle_prompt) will correlate it
        if let message = event.lastAssistantMessage, !message.isEmpty {
            lastStopData[event.sessionId] = (message: message, cwd: event.cwd)
            logger.debug("Buffered Stop message for session \(event.sessionId): \(message.prefix(80))...")
        }
    }

    private func handleNotification(_ event: HookEvent) {
        guard event.notificationType == "idle_prompt" else {
            logger.debug("Ignoring notification type: \(event.notificationType ?? "nil")")
            return
        }

        let sessionId = event.sessionId

        // Don't show idle prompt if a permission prompt is active
        guard sessionQueues[sessionId]?.isIdle ?? true else {
            logger.debug("Skipping idle prompt — permission prompt active for session \(sessionId)")
            return
        }

        // Use the buffered Stop message for the question text
        let stopData = lastStopData.removeValue(forKey: sessionId)
        guard let questionText = stopData?.message, !questionText.isEmpty else {
            logger.debug("Idle prompt with no Stop message for session \(sessionId)")
            return
        }

        let info = IdlePromptInfo(sessionId: sessionId, lastAssistantMessage: questionText, cwd: stopData?.cwd ?? event.cwd)
        pendingIdlePrompts[sessionId] = info

        logger.info("Idle prompt for session \(sessionId): \(questionText.prefix(80))...")

        onIdlePromptReceived?(info)
        onForwardIdleToiOS?(info)
    }

    // MARK: - PTY Output Monitoring

    /// Called from the PTY output callback. The sessionId here is the PTY session ID,
    /// which we resolve to the Claude Code session ID for prompt lookup.
    func handlePTYOutput(ptySessionId: String, byteCount: Int) {
        // Resolve PTY session ID to Claude Code session ID
        guard let claudeSessionId = ptyToClaudeSessionId[ptySessionId] else { return }

        // Dismiss idle prompt on any PTY output (user started typing or Claude resumed)
        if pendingIdlePrompts[claudeSessionId] != nil {
            dismissIdlePrompt(for: claudeSessionId)
        }

        guard var sq = sessionQueues[claudeSessionId], sq.activeInfo != nil else { return }

        sq.outputSincePrompt += byteCount
        sessionQueues[claudeSessionId] = sq

        if sq.outputSincePrompt >= Self.dismissOutputThreshold {
            logger.info("Auto-dismissing prompt for session \(claudeSessionId) — \(sq.outputSincePrompt) bytes of new output")
            dismissPrompt(for: claudeSessionId)
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
    }

    // MARK: - Private

    /// Activate a prompt: set state, update published snapshot, notify all surfaces,
    /// and schedule a stale timeout.
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
