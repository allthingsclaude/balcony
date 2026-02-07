import Foundation
import BalconyShared
import os

/// Manages Claude Code sessions received from the connected Mac.
@MainActor
final class SessionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "SessionManager")

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?
    @Published var terminalMessages: [SessionMessage] = []

    private weak var connectionManager: ConnectionManager?

    // MARK: - Configuration

    /// Wire up the connection manager to send/receive session messages.
    func configure(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        connectionManager.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }
    }

    // MARK: - Session Actions

    /// Refresh the session list from the connected Mac.
    func refreshSessions() async {
        logger.info("Refreshing sessions")
        guard let connectionManager else {
            logger.warning("No connection manager configured")
            return
        }
        do {
            // Send an empty sessionList request — Mac responds with the full list
            let msg = try BalconyMessage.create(type: .sessionList, payload: EmptyPayload())
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to request session list: \(error.localizedDescription)")
        }
    }

    /// Subscribe to real-time updates for a session.
    func subscribe(to session: Session) async {
        logger.info("Subscribing to session: \(session.id)")
        activeSession = session
        terminalMessages = []

        guard let connectionManager else { return }
        do {
            let payload = SessionSubscribePayload(sessionId: session.id)
            let msg = try BalconyMessage.create(type: .sessionSubscribe, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to subscribe to session: \(error.localizedDescription)")
        }
    }

    /// Unsubscribe from a session.
    func unsubscribe(from session: Session) async {
        logger.info("Unsubscribing from session: \(session.id)")
        if activeSession?.id == session.id {
            activeSession = nil
            terminalMessages = []
        }

        guard let connectionManager else { return }
        do {
            let payload = SessionSubscribePayload(sessionId: session.id)
            let msg = try BalconyMessage.create(type: .sessionUnsubscribe, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to unsubscribe from session: \(error.localizedDescription)")
        }
    }

    /// Send user input to a session on the Mac.
    func sendInput(_ input: String, to session: Session) async {
        logger.info("Sending input to session: \(session.id)")
        guard let connectionManager else { return }
        do {
            let payload = UserInputPayload(sessionId: session.id, text: input)
            let msg = try BalconyMessage.create(type: .userInput, payload: payload)
            try await connectionManager.send(msg)
        } catch {
            logger.error("Failed to send input: \(error.localizedDescription)")
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: BalconyMessage) {
        switch message.type {
        case .sessionList:
            handleSessionList(message)
        case .sessionUpdate:
            handleSessionUpdate(message)
        case .terminalOutput:
            handleTerminalOutput(message)
        case .toolUseStart, .toolUseEnd:
            handleToolUseEvent(message)
        default:
            break
        }
    }

    private func handleSessionList(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SessionListPayload.self)
            sessions = payload.sessions
            logger.info("Received session list: \(payload.sessions.count) sessions")
        } catch {
            logger.error("Failed to decode session list: \(error.localizedDescription)")
        }
    }

    private func handleSessionUpdate(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SessionUpdatePayload.self)
            if let index = sessions.firstIndex(where: { $0.id == payload.session.id }) {
                sessions[index] = payload.session
            } else {
                sessions.append(payload.session)
            }
            // Update activeSession if it's the one being viewed
            if activeSession?.id == payload.session.id {
                activeSession = payload.session
            }
            logger.debug("Session updated: \(payload.session.id)")
        } catch {
            logger.error("Failed to decode session update: \(error.localizedDescription)")
        }
    }

    private func handleTerminalOutput(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(TerminalOutputPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            terminalMessages.append(payload.message)
            logger.debug("Terminal output for \(payload.sessionId)")
        } catch {
            logger.error("Failed to decode terminal output: \(error.localizedDescription)")
        }
    }

    private func handleToolUseEvent(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(ToolUseEventPayload.self)
            logger.debug("Tool use event: \(payload.toolName) for \(payload.sessionId)")
        } catch {
            logger.error("Failed to decode tool use event: \(error.localizedDescription)")
        }
    }
}

// MARK: - Message Payloads (must match Mac-side definitions)

/// Empty payload for request-style messages.
struct EmptyPayload: Codable, Sendable {}

/// Payload for session list responses from Mac.
struct SessionListPayload: Codable, Sendable {
    let sessions: [Session]
}

/// Payload for session update messages from Mac.
struct SessionUpdatePayload: Codable, Sendable {
    let session: Session
}

/// Payload for terminal output messages from Mac.
struct TerminalOutputPayload: Codable, Sendable {
    let sessionId: String
    let message: SessionMessage
}

/// Payload for tool use event messages from Mac.
struct ToolUseEventPayload: Codable, Sendable {
    let sessionId: String
    let toolName: String
    let content: String
}

/// Payload for session subscribe/unsubscribe messages to Mac.
struct SessionSubscribePayload: Codable, Sendable {
    let sessionId: String
}

/// Payload for user input messages to Mac.
struct UserInputPayload: Codable, Sendable {
    let sessionId: String
    let text: String
}
