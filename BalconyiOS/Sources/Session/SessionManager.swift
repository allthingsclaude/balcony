import Foundation
import BalconyShared
import os

/// Manages Claude Code sessions received from the connected Mac.
@MainActor
final class SessionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "SessionManager")

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?

    /// Refresh the session list from the connected Mac.
    func refreshSessions() async {
        logger.info("Refreshing sessions")
        // TODO: Request session list from Mac via WebSocket
    }

    /// Subscribe to real-time updates for a session.
    func subscribe(to session: Session) async {
        logger.info("Subscribing to session: \(session.id)")
        activeSession = session
        // TODO: Send sessionSubscribe message
    }

    /// Unsubscribe from a session.
    func unsubscribe(from session: Session) async {
        logger.info("Unsubscribing from session: \(session.id)")
        if activeSession?.id == session.id {
            activeSession = nil
        }
        // TODO: Send sessionUnsubscribe message
    }

    /// Send user input to a session on the Mac.
    func sendInput(_ input: String, to session: Session) async {
        logger.info("Sending input to session: \(session.id)")
        // TODO: Send userInput message via WebSocket
    }
}
