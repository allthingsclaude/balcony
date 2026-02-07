import Foundation
import BalconyShared
import os

/// Coordinates all connection components (WebSocket, Bonjour, BLE)
/// and bridges SessionMonitor/HookManager events to connected iOS clients.
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "ConnectionManager")

    @Published var connectedDevices: [DeviceInfo] = []
    @Published var isServerRunning = false

    private let webSocketServer: WebSocketServer
    private let bonjourAdvertiser: BonjourAdvertiser
    private let blePeripheral: BLEPeripheral
    private let sessionMonitor: SessionMonitor

    private let encoder = MessageEncoder()
    private var serverEventTask: Task<Void, Never>?

    init(
        port: Int = 29170,
        sessionMonitor: SessionMonitor
    ) {
        self.webSocketServer = WebSocketServer(port: port)
        self.bonjourAdvertiser = BonjourAdvertiser(port: UInt16(port))
        self.blePeripheral = BLEPeripheral()
        self.sessionMonitor = sessionMonitor
    }

    // MARK: - Lifecycle

    /// Start all connection services.
    func start() async throws {
        logger.info("Starting connection services")

        // Start WebSocket server and consume its event stream
        let serverEvents = try await webSocketServer.start()
        serverEventTask = Task { [weak self] in
            for await event in serverEvents {
                await self?.handleServerEvent(event)
            }
        }

        // Start Bonjour advertising
        try await bonjourAdvertiser.startAdvertising(publicKeyFingerprint: "")

        // Start BLE peripheral
        blePeripheral.startAdvertising(deviceName: Host.current().localizedName ?? "Mac")

        isServerRunning = true
        logger.info("All connection services started")
    }

    /// Stop all connection services.
    func stop() async throws {
        serverEventTask?.cancel()
        serverEventTask = nil
        try await webSocketServer.stop()
        await bonjourAdvertiser.stopAdvertising()
        blePeripheral.stopAdvertising()
        connectedDevices = []
        isServerRunning = false
        logger.info("All connection services stopped")
    }

    // MARK: - Session Event Forwarding

    /// Forward a session event from SessionMonitor to connected iOS clients.
    func forwardSessionEvent(_ event: SessionEvent) async {
        switch event {
        case .sessionDiscovered(let session):
            // Broadcast updated session list to all authenticated clients
            await broadcastSessionList()
            logger.info("Forwarded session discovered: \(session.id)")

        case .sessionUpdated(let session, let newMessages):
            // Send terminal output to subscribers of this session
            for message in newMessages {
                do {
                    let outputPayload = TerminalOutputPayload(
                        sessionId: session.id,
                        message: message
                    )
                    let msg = try BalconyMessage.create(type: .terminalOutput, payload: outputPayload)
                    await webSocketServer.sendToSubscribers(of: session.id, message: msg)
                } catch {
                    logger.error("Failed to create terminal output message: \(error.localizedDescription)")
                }
            }

            // Broadcast session update to all clients
            do {
                let updatePayload = SessionUpdatePayload(session: session)
                let msg = try BalconyMessage.create(type: .sessionUpdate, payload: updatePayload)
                await webSocketServer.broadcast(msg)
            } catch {
                logger.error("Failed to create session update message: \(error.localizedDescription)")
            }

        case .sessionEnded(let sessionId):
            await broadcastSessionList()
            logger.info("Forwarded session ended: \(sessionId)")
        }
    }

    // MARK: - Hook Event Forwarding

    /// Forward a hook event from HookManager to connected iOS clients.
    func forwardHookEvent(_ event: HookEvent) async {
        switch event {
        case .preToolUse(let sessionId, let toolName, let input):
            do {
                let payload = ToolUseEventPayload(
                    sessionId: sessionId,
                    toolName: toolName,
                    content: input
                )
                let msg = try BalconyMessage.create(type: .toolUseStart, payload: payload)
                await webSocketServer.sendToSubscribers(of: sessionId, message: msg)
            } catch {
                logger.error("Failed to forward preToolUse: \(error.localizedDescription)")
            }

        case .postToolUse(let sessionId, let toolName, let output):
            do {
                let payload = ToolUseEventPayload(
                    sessionId: sessionId,
                    toolName: toolName,
                    content: output
                )
                let msg = try BalconyMessage.create(type: .toolUseEnd, payload: payload)
                await webSocketServer.sendToSubscribers(of: sessionId, message: msg)
            } catch {
                logger.error("Failed to forward postToolUse: \(error.localizedDescription)")
            }

        case .notification(let sessionId, let message):
            logger.info("Hook notification for \(sessionId): \(message)")

        case .sessionStop(let sessionId):
            await broadcastSessionList()
            logger.info("Hook: session stopped \(sessionId)")
        }
    }

    // MARK: - Server Event Handling

    private func handleServerEvent(_ event: WebSocketServerEvent) async {
        switch event {
        case .clientConnected(let client):
            logger.info("Client connected: \(client.id)")

        case .clientAuthenticated(let client, let deviceInfo):
            connectedDevices.append(deviceInfo)
            logger.info("Client authenticated: \(deviceInfo.name)")

            // Send session list to newly authenticated client
            await sendSessionList(to: client)

        case .clientDisconnected(let client):
            if let info = client.deviceInfo {
                connectedDevices.removeAll { $0.id == info.id }
            }
            logger.info("Client disconnected: \(client.id)")

        case .messageReceived(let client, let message):
            await handleClientMessage(from: client, message: message)
        }
    }

    private func handleClientMessage(from client: ConnectedClient, message: BalconyMessage) async {
        switch message.type {
        case .userInput:
            // Forward user input to the appropriate session
            do {
                let input = try message.decodePayload(UserInputPayload.self)
                logger.info("User input for session \(input.sessionId): \(input.text.prefix(50))")
                // TODO: Phase 1.8 - Write input to session via stdin or hook
            } catch {
                logger.error("Failed to decode user input: \(error.localizedDescription)")
            }

        default:
            logger.debug("Unhandled client message type: \(message.type.rawValue)")
        }
    }

    // MARK: - Session List

    private func broadcastSessionList() async {
        let sessions = await sessionMonitor.getSessions()
        do {
            let payload = SessionListPayload(sessions: sessions)
            let msg = try BalconyMessage.create(type: .sessionList, payload: payload)
            await webSocketServer.broadcast(msg)
        } catch {
            logger.error("Failed to broadcast session list: \(error.localizedDescription)")
        }
    }

    private func sendSessionList(to client: ConnectedClient) async {
        let sessions = await sessionMonitor.getSessions()
        do {
            let payload = SessionListPayload(sessions: sessions)
            let msg = try BalconyMessage.create(type: .sessionList, payload: payload)
            await webSocketServer.send(msg, to: client)
        } catch {
            logger.error("Failed to send session list to \(client.id): \(error.localizedDescription)")
        }
    }
}

// MARK: - Message Payloads

/// Payload for session list messages.
struct SessionListPayload: Codable, Sendable {
    let sessions: [Session]
}

/// Payload for session update messages.
struct SessionUpdatePayload: Codable, Sendable {
    let session: Session
}

/// Payload for terminal output messages.
struct TerminalOutputPayload: Codable, Sendable {
    let sessionId: String
    let message: SessionMessage
}

/// Payload for tool use event messages.
struct ToolUseEventPayload: Codable, Sendable {
    let sessionId: String
    let toolName: String
    let content: String
}

/// Payload for user input messages from iOS.
struct UserInputPayload: Codable, Sendable {
    let sessionId: String
    let text: String
}
