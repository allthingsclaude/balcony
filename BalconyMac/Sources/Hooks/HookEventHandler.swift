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

        // Store as pending
        pendingPrompts[promptInfo.sessionId] = promptInfo

        // Notify Mac UI
        onPromptReceived?(promptInfo)

        // Forward to iOS
        onForwardToiOS?(promptInfo)
    }

    // MARK: - Dismissal

    /// Dismiss the pending prompt for a session (called when the prompt is answered).
    func dismissPrompt(for sessionId: String) {
        guard pendingPrompts.removeValue(forKey: sessionId) != nil else { return }
        logger.info("Prompt dismissed for session: \(sessionId)")
        onPromptDismissed?(sessionId)
    }

    /// Check if a session has a pending prompt.
    func hasPendingPrompt(for sessionId: String) -> Bool {
        pendingPrompts[sessionId] != nil
    }
}
