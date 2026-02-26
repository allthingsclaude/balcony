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

    /// When the current prompt was received (for stale detection).
    var activeSince: Date?

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

    // MARK: - Callbacks

    /// Called when a new permission prompt should be shown on Mac.
    var onPromptReceived: ((PermissionPromptInfo) -> Void)?

    /// Called when a prompt is dismissed (answered from any surface).
    var onPromptDismissed: ((String) -> Void)?

    /// Called to forward hook events to iOS via WebSocket.
    var onForwardToiOS: ((PermissionPromptInfo) -> Void)?

    // MARK: - Configuration

    /// Timeout for stale hook events that never get a response or PTY confirmation.
    /// If a prompt is still active after this duration with no new PTY output,
    /// it is likely a ghost event and should be discarded.
    private static let staleHookTimeout: TimeInterval = 10.0

    /// Threshold of new PTY output bytes that indicates the prompt was answered
    /// and Claude Code has moved on to producing new output.
    private static let dismissOutputThreshold = 200

    // MARK: - Event Processing

    /// Handle a raw hook event from HookListener.
    func handleHookEvent(_ event: HookEvent) {
        guard event.hookEventName == "PermissionRequest" else {
            logger.debug("Ignoring non-permission hook event: \(event.hookEventName)")
            return
        }

        guard let promptInfo = PermissionPromptInfo.from(event) else {
            logger.warning("Could not parse PermissionPromptInfo from hook event")
            return
        }

        logger.info("Permission prompt: \(promptInfo.toolName) risk=\(promptInfo.riskLevel.rawValue) session=\(promptInfo.sessionId)")

        let sessionId = promptInfo.sessionId
        var sq = sessionQueues[sessionId] ?? SessionPromptQueue()

        if sq.isIdle {
            // No active prompt — activate immediately
            activatePrompt(promptInfo, in: &sq)
            sessionQueues[sessionId] = sq
        } else {
            // Active prompt exists — enqueue for later
            sq.queue.append(promptInfo)
            sessionQueues[sessionId] = sq
            logger.info("Queued prompt for session \(sessionId) — queue depth: \(sq.queue.count)")
        }
    }

    // MARK: - PTY Output Monitoring

    /// Called from the PTY output callback. If a prompt is active for this session
    /// and enough new output has arrived, the prompt was likely answered — auto-dismiss.
    func handlePTYOutput(sessionId: String, byteCount: Int) {
        guard var sq = sessionQueues[sessionId], sq.activeInfo != nil else { return }

        sq.outputSincePrompt += byteCount
        sessionQueues[sessionId] = sq

        if sq.outputSincePrompt >= Self.dismissOutputThreshold {
            logger.info("Auto-dismissing prompt for session \(sessionId) — \(sq.outputSincePrompt) bytes of new output")
            dismissPrompt(for: sessionId)
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
        sq.activeSince = nil

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

    // MARK: - Queries

    /// Check if a session has an active prompt.
    func hasPendingPrompt(for sessionId: String) -> Bool {
        sessionQueues[sessionId]?.activeInfo != nil
    }

    /// Get the current active prompt info (e.g., for resending to a reconnecting iOS client).
    func pendingPrompt(for sessionId: String) -> PermissionPromptInfo? {
        sessionQueues[sessionId]?.activeInfo
    }

    // MARK: - Session Lifecycle

    /// Clear all prompt state for a session that has ended.
    func sessionEnded(_ sessionId: String) {
        if sessionQueues.removeValue(forKey: sessionId) != nil {
            pendingPrompts.removeValue(forKey: sessionId)
            logger.debug("Cleared prompt state for ended session: \(sessionId)")
        }
    }

    // MARK: - Private

    /// Activate a prompt: set state, update published snapshot, notify all surfaces,
    /// and schedule a stale timeout.
    private func activatePrompt(_ info: PermissionPromptInfo, in sq: inout SessionPromptQueue) {
        let sessionId = info.sessionId

        sq.state = .active(info)
        sq.outputSincePrompt = 0
        sq.activeSince = Date()

        pendingPrompts[sessionId] = info

        // Notify Mac panel
        onPromptReceived?(info)

        // Forward to iOS
        onForwardToiOS?(info)

        // Schedule stale check
        let activationTime = sq.activeSince!
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.staleHookTimeout))
            self?.checkStale(sessionId: sessionId, activationTime: activationTime)
        }
    }

    /// If a prompt is still active with zero PTY output after the timeout,
    /// it's likely a ghost event — discard it.
    private func checkStale(sessionId: String, activationTime: Date) {
        guard let sq = sessionQueues[sessionId],
              let activeSince = sq.activeSince,
              activeSince == activationTime,
              sq.outputSincePrompt == 0 else { return }

        logger.warning("Stale hook event discarded for session \(sessionId) — no PTY activity after \(Self.staleHookTimeout)s")
        dismissPrompt(for: sessionId)
    }
}
