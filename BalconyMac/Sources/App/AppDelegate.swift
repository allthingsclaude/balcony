import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AppDelegate")

    private let sessionMonitor = SessionMonitor()
    private let hookManager = HookManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")

        Task {
            // Start session file monitoring
            let sessionEvents = await sessionMonitor.startMonitoring()

            // Install hooks and start listening
            do {
                try await hookManager.installHooks()
            } catch {
                logger.error("Failed to install hooks: \(error.localizedDescription)")
            }
            let hookEvents = await hookManager.startListening()

            // Process session events
            Task {
                for await event in sessionEvents {
                    await handleSessionEvent(event)
                }
            }

            // Process hook events
            Task {
                for await event in hookEvents {
                    await handleHookEvent(event)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("BalconyMac terminating")

        Task {
            await sessionMonitor.stopMonitoring()
            await hookManager.stopListening()
            try? await hookManager.removeHooks()
        }
    }

    // MARK: - Event Routing

    @MainActor
    private func handleSessionEvent(_ event: SessionEvent) {
        switch event {
        case .sessionDiscovered(let session):
            logger.info("Session discovered: \(session.id)")
            // TODO: Forward to ConnectionManager for broadcast to iOS clients
        case .sessionUpdated(let session, let messages):
            logger.debug("Session \(session.id) updated with \(messages.count) new messages")
            // TODO: Forward to ConnectionManager
        case .sessionEnded(let sessionId):
            logger.info("Session ended: \(sessionId)")
            // TODO: Forward to ConnectionManager
        }
    }

    @MainActor
    private func handleHookEvent(_ event: HookEvent) {
        switch event {
        case .preToolUse(let sessionId, let toolName, _):
            logger.debug("Pre-tool: \(toolName) in \(sessionId)")
            // TODO: Forward to ConnectionManager
        case .postToolUse(let sessionId, let toolName, _):
            logger.debug("Post-tool: \(toolName) in \(sessionId)")
            // TODO: Forward to ConnectionManager
        case .notification(let sessionId, let message):
            logger.info("Notification for \(sessionId): \(message)")
            // TODO: Forward to ConnectionManager
        case .sessionStop(let sessionId):
            logger.info("Hook: session stopped \(sessionId)")
            Task { await sessionMonitor.endSession(id: sessionId) }
        }
    }
}
