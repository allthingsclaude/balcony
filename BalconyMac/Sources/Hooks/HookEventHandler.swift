import Foundation
import BalconyShared
import os

/// Processes hook events from Claude Code, manages pending prompts,
/// and notifies the UI layer and iOS clients.
@MainActor
final class HookEventHandler: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "HookEventHandler")

    /// The currently pending permission prompt per session.
    @Published private(set) var pendingPrompts: [String: PermissionPromptInfo] = [:]

    /// Called when a new permission prompt should be shown on Mac.
    var onPromptReceived: ((PermissionPromptInfo) -> Void)?

    /// Called when a prompt is dismissed (answered from any surface).
    var onPromptDismissed: ((String) -> Void)?

    /// Called to forward hook events to iOS via WebSocket.
    var onForwardToiOS: ((PermissionPromptInfo) -> Void)?

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

        // Store as pending, reset output counter
        pendingPrompts[promptInfo.sessionId] = promptInfo
        outputSincePrompt[promptInfo.sessionId] = 0

        // Notify Mac UI
        onPromptReceived?(promptInfo)

        // Forward to iOS
        onForwardToiOS?(promptInfo)
    }

    // MARK: - PTY Output Monitoring

    /// Bytes of PTY output received per session since the prompt was shown.
    private var outputSincePrompt: [String: Int] = [:]

    /// Threshold of new PTY output bytes that indicates the prompt was answered
    /// and Claude Code has moved on.
    private static let dismissOutputThreshold = 200

    /// Called from the PTY output callback. If a prompt is pending for this
    /// session and enough new output has arrived, the prompt was likely answered
    /// from the terminal — auto-dismiss.
    func handlePTYOutput(sessionId: String, byteCount: Int) {
        guard pendingPrompts[sessionId] != nil else { return }

        let accumulated = (outputSincePrompt[sessionId] ?? 0) + byteCount
        outputSincePrompt[sessionId] = accumulated

        if accumulated >= Self.dismissOutputThreshold {
            logger.info("Auto-dismissing prompt for session \(sessionId) — \(accumulated) bytes of new output")
            dismissPrompt(for: sessionId)
        }
    }

    // MARK: - Dismissal

    /// Dismiss the pending prompt for a session (called when the prompt is answered).
    func dismissPrompt(for sessionId: String) {
        guard pendingPrompts.removeValue(forKey: sessionId) != nil else { return }
        outputSincePrompt.removeValue(forKey: sessionId)
        logger.info("Prompt dismissed for session: \(sessionId)")
        onPromptDismissed?(sessionId)
    }

    /// Check if a session has a pending prompt.
    func hasPendingPrompt(for sessionId: String) -> Bool {
        pendingPrompts[sessionId] != nil
    }
}
