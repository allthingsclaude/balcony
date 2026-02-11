import Foundation
import BalconyShared
import os

/// Coordinates all connection components (WebSocket, Bonjour, BLE)
/// and bridges PTY session data to connected iOS clients.
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "ConnectionManager")

    @Published var connectedDevices: [DeviceInfo] = []
    @Published var isServerRunning = false

    /// Icon name reflecting current connection state for the menu bar.
    var statusIconName: String {
        if !isServerRunning {
            return "antenna.radiowaves.left.and.right.slash"
        } else if !connectedDevices.isEmpty {
            return "antenna.radiowaves.left.and.right.circle.fill"
        } else {
            return "antenna.radiowaves.left.and.right"
        }
    }

    private let webSocketServer: WebSocketServer
    private let bonjourAdvertiser: BonjourAdvertiser
    private let blePeripheral: BLEPeripheral
    private let ptySessionManager: PTYSessionManager

    /// Server identity crypto manager used for QR code pairing.
    let serverCrypto = CryptoManager()
    private let port: Int
    private let encoder = MessageEncoder()
    private var serverEventTask: Task<Void, Never>?

    init(
        port: Int = 29170,
        ptySessionManager: PTYSessionManager
    ) {
        self.port = port
        self.webSocketServer = WebSocketServer(port: port)
        self.bonjourAdvertiser = BonjourAdvertiser(port: UInt16(port))
        self.blePeripheral = BLEPeripheral()
        self.ptySessionManager = ptySessionManager
    }

    /// Generate the pairing URL containing host, port, and public key.
    func generatePairingURL() async throws -> String {
        _ = try await serverCrypto.generateKeyPair()
        let publicKeyBase64 = try await serverCrypto.publicKeyBase64()
        let host = ProcessInfo.processInfo.hostName
        var components = URLComponents()
        components.scheme = "balcony"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "pk", value: publicKeyBase64),
        ]
        return components.string ?? "balcony://pair?host=\(host)&port=\(port)&pk=\(publicKeyBase64)"
    }

    // MARK: - Lifecycle

    func start() async throws {
        logger.info("Starting connection services")

        let serverEvents = try await webSocketServer.start()
        serverEventTask = Task { [weak self] in
            for await event in serverEvents {
                await self?.handleServerEvent(event)
            }
        }

        let keyPair = try await serverCrypto.generateKeyPair()
        bonjourAdvertiser.startAdvertising(publicKeyFingerprint: keyPair.fingerprint)
        blePeripheral.startAdvertising(deviceName: Host.current().localizedName ?? "Mac")

        isServerRunning = true
        logger.info("All connection services started")
    }

    func stop() async throws {
        serverEventTask?.cancel()
        serverEventTask = nil
        try await webSocketServer.stop()
        bonjourAdvertiser.stopAdvertising()
        blePeripheral.stopAdvertising()
        connectedDevices = []
        isServerRunning = false
        logger.info("All connection services stopped")
    }

    // MARK: - PTY Data Forwarding

    /// Forward raw PTY output from a CLI session to WebSocket subscribers.
    func forwardPTYOutput(sessionId: String, data: Data) async {
        do {
            let payload = TerminalDataPayload(sessionId: sessionId, data: data)
            let msg = try BalconyMessage.create(type: .terminalData, payload: payload)
            await webSocketServer.sendToSubscribers(of: sessionId, message: msg)
        } catch {
            logger.error("Failed to forward PTY output: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Event Forwarding

    /// Forward a PTY session event to connected iOS clients.
    func forwardSessionEvent(_ event: SessionEvent) async {
        switch event {
        case .sessionDiscovered:
            await broadcastSessionList()
        case .sessionEnded:
            await broadcastSessionList()
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
        case .sessionList:
            await sendSessionList(to: client)

        case .sessionSubscribe:
            do {
                let payload = try message.decodePayload(SessionSubscribePayload.self)
                let sessionId = payload.sessionId
                logger.info("Client subscribed to PTY session \(sessionId)")

                // Send buffered PTY history so iOS gets the full conversation.
                // Chunk large buffers to avoid exceeding WebSocket message size limits.
                if let buffer = await ptySessionManager.getSessionBuffer(sessionId), !buffer.isEmpty {
                    let chunkSize = 512 * 1024 // 512 KB raw → ~750 KB after base64/JSON encoding
                    var offset = 0
                    while offset < buffer.count {
                        let end = min(offset + chunkSize, buffer.count)
                        let chunk = buffer[offset..<end]
                        let historyPayload = TerminalDataPayload(sessionId: sessionId, data: Data(chunk))
                        let historyMsg = try BalconyMessage.create(type: .terminalData, payload: historyPayload)
                        await webSocketServer.send(historyMsg, to: client)
                        offset = end
                    }
                }

                // Send available slash commands for this session's project.
                await sendSlashCommands(sessionId: sessionId, to: client)
            } catch {
                logger.error("Failed to decode session subscribe: \(error.localizedDescription)")
            }

        case .userInput:
            do {
                let input = try message.decodePayload(UserInputPayload.self)
                if let data = input.text.data(using: .utf8) {
                    await ptySessionManager.sendInput(sessionId: input.sessionId, data: data)
                }
                logger.info("Delivered input to PTY for session \(input.sessionId)")
            } catch {
                logger.error("Failed to deliver user input: \(error.localizedDescription)")
            }

        case .terminalResize:
            do {
                let payload = try message.decodePayload(TerminalResizePayload.self)
                await ptySessionManager.sendResize(
                    sessionId: payload.sessionId,
                    cols: payload.cols,
                    rows: payload.rows
                )
            } catch {
                logger.error("Failed to forward terminal resize: \(error.localizedDescription)")
            }

        default:
            logger.debug("Unhandled client message type: \(message.type.rawValue)")
        }
    }

    // MARK: - Slash Commands

    private func sendSlashCommands(sessionId: String, to client: ConnectedClient) async {
        let sessions = await ptySessionManager.getActiveSessions()
        guard let session = sessions.first(where: { $0.id == sessionId }) else { return }

        let projectPath = session.projectPath
        let commands = SlashCommandScanner.scan(projectPath: projectPath)

        do {
            let payload = SlashCommandsPayload(sessionId: sessionId, commands: commands)
            let msg = try BalconyMessage.create(type: .slashCommands, payload: payload)
            await webSocketServer.send(msg, to: client)
            logger.info("Sent \(commands.count) slash commands for session \(sessionId)")
        } catch {
            logger.error("Failed to send slash commands: \(error.localizedDescription)")
        }
    }

    // MARK: - Session List

    private func broadcastSessionList() async {
        let sessions = await ptySessionManager.getActiveSessions()
        do {
            let payload = SessionListPayload(sessions: sessions)
            let msg = try BalconyMessage.create(type: .sessionList, payload: payload)
            await webSocketServer.broadcast(msg)
        } catch {
            logger.error("Failed to broadcast session list: \(error.localizedDescription)")
        }
    }

    private func sendSessionList(to client: ConnectedClient) async {
        let sessions = await ptySessionManager.getActiveSessions()
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
