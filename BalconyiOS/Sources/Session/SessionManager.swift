import Foundation
import BalconyShared
import Combine
import os

/// Manages Claude Code sessions received from the connected Mac.
@MainActor
final class SessionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "SessionManager")

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?

    /// Parsed conversation lines from the headless terminal parser.
    @Published var conversationLines: [TerminalLine] = []

    /// Slash commands available for the active session.
    @Published var slashCommands: [SlashCommandInfo] = []

    /// Detected interactive prompt (permission or multi-option) from terminal output.
    @Published var activePrompt: InteractivePrompt?

    private var parser: HeadlessTerminalParser?
    private var parserCancellable: AnyCancellable?
    private var promptCancellable: AnyCancellable?

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
        conversationLines = []
        slashCommands = []

        let cols = Int(session.cols ?? 80)
        let rows = Int(session.rows ?? 24)
        let newParser = HeadlessTerminalParser(cols: cols, rows: rows)
        self.parser = newParser
        parserCancellable = newParser.$conversationLines
            .receive(on: DispatchQueue.main)
            .assign(to: \.conversationLines, on: self)
        promptCancellable = newParser.$activePrompt
            .receive(on: DispatchQueue.main)
            .assign(to: \.activePrompt, on: self)

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
            parserCancellable?.cancel()
            parserCancellable = nil
            promptCancellable?.cancel()
            promptCancellable = nil
            parser = nil
            conversationLines = []
            activePrompt = nil
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
        case .terminalData:
            handleTerminalData(message)
        case .slashCommands:
            handleSlashCommands(message)
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
            if activeSession?.id == payload.session.id {
                activeSession = payload.session
            }
            logger.debug("Session updated: \(payload.session.id)")
        } catch {
            logger.error("Failed to decode session update: \(error.localizedDescription)")
        }
    }

    private func handleTerminalData(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(TerminalDataPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            parser?.feed(bytes: Array(payload.data))
            logger.debug("Terminal data for \(payload.sessionId): \(payload.data.count) bytes")
        } catch {
            logger.error("Failed to decode terminal data: \(error.localizedDescription)")
        }
    }

    private func handleSlashCommands(_ message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SlashCommandsPayload.self)
            guard payload.sessionId == activeSession?.id else { return }
            slashCommands = payload.commands
            logger.info("Received \(payload.commands.count) slash commands")
        } catch {
            logger.error("Failed to decode slash commands: \(error.localizedDescription)")
        }
    }
}

// MARK: - Message Payloads

struct EmptyPayload: Codable, Sendable {}

struct SessionListPayload: Codable, Sendable {
    let sessions: [Session]
}

struct SessionUpdatePayload: Codable, Sendable {
    let session: Session
}

struct SessionSubscribePayload: Codable, Sendable {
    let sessionId: String
}

struct UserInputPayload: Codable, Sendable {
    let sessionId: String
    let text: String
}
