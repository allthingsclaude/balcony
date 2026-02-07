import AppKit
import BalconyShared
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AppDelegate")

    private let sessionMonitor = SessionMonitor()
    private let hookManager = HookManager()
    private lazy var connectionManager = ConnectionManager(sessionMonitor: sessionMonitor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("BalconyMac launched")

        Task {
            // Start connection services (WebSocket server, Bonjour, BLE)
            do {
                try await connectionManager.start()
            } catch {
                logger.error("Failed to start connection services: \(error.localizedDescription)")
            }

            // Start session file monitoring
            let sessionEvents = await sessionMonitor.startMonitoring()

            // Install hooks and start listening
            do {
                try await hookManager.installHooks()
            } catch {
                logger.error("Failed to install hooks: \(error.localizedDescription)")
            }
            let hookEvents = await hookManager.startListening()

            // Process session events -> forward to connected iOS clients
            Task {
                for await event in sessionEvents {
                    await handleSessionEvent(event)
                }
            }

            // Process hook events -> forward to connected iOS clients
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
            try? await connectionManager.stop()
            await sessionMonitor.stopMonitoring()
            await hookManager.stopListening()
            try? await hookManager.removeHooks()
        }
    }

    // MARK: - Event Routing

    @MainActor
    private func handleSessionEvent(_ event: SessionEvent) async {
        switch event {
        case .sessionDiscovered(let session):
            logger.info("Session discovered: \(session.id)")
        case .sessionUpdated(let session, let messages):
            logger.debug("Session \(session.id) updated with \(messages.count) new messages")
        case .sessionEnded(let sessionId):
            logger.info("Session ended: \(sessionId)")
        }

        // Forward all session events to connected iOS clients
        await connectionManager.forwardSessionEvent(event)
    }

    @MainActor
    private func handleHookEvent(_ event: HookEvent) async {
        switch event {
        case .preToolUse(let sessionId, let toolName, _):
            logger.debug("Pre-tool: \(toolName) in \(sessionId)")
        case .postToolUse(let sessionId, let toolName, _):
            logger.debug("Post-tool: \(toolName) in \(sessionId)")
        case .notification(let sessionId, let message):
            logger.info("Notification for \(sessionId): \(message)")
        case .sessionStop(let sessionId):
            logger.info("Hook: session stopped \(sessionId)")
            Task { await sessionMonitor.endSession(id: sessionId) }
        }

        // Forward all hook events to connected iOS clients
        await connectionManager.forwardHookEvent(event)
    }
}
