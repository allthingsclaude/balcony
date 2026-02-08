import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket
import BalconyShared
import os

// MARK: - WebSocket Server Events

/// Events emitted by the WebSocket server for upstream consumption.
enum WebSocketServerEvent: Sendable {
    case clientConnected(ConnectedClient)
    case clientAuthenticated(ConnectedClient, DeviceInfo)
    case clientDisconnected(ConnectedClient)
    case messageReceived(ConnectedClient, BalconyMessage)
}

// MARK: - WebSocket Server

/// WebSocket server for iOS client connections using SwiftNIO.
actor WebSocketServer {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "WebSocketServer")
    private var group: EventLoopGroup?
    private var channel: Channel?
    private let port: Int

    private var clients: [String: ConnectedClient] = [:]
    private var eventContinuation: AsyncStream<WebSocketServerEvent>.Continuation?
    private var heartbeatTask: RepeatedTask?

    private let encoder = MessageEncoder()
    private let decoder = MessageDecoder()

    init(port: Int = 29170) {
        self.port = port
    }

    // MARK: - Server Lifecycle

    /// Start the WebSocket server and return a stream of server events.
    func start() async throws -> AsyncStream<WebSocketServerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: WebSocketServerEvent.self)
        self.eventContinuation = continuation

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group

        let server = self

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let upgrader = NIOWebSocketServerUpgrader(
                    shouldUpgrade: { channel, head in
                        channel.eventLoop.makeSucceededFuture(HTTPHeaders())
                    },
                    upgradePipelineHandler: { channel, req in
                        let client = ConnectedClient(channel: channel)
                        Task { await server.clientDidConnect(client) }

                        let handler = WebSocketFrameHandler(
                            client: client,
                            onMessage: { client, data in
                                Task { await server.handleRawMessage(from: client, data: data) }
                            },
                            onDisconnect: { client in
                                Task { await server.clientDidDisconnect(client) }
                            }
                        )
                        return channel.pipeline.addHandler(handler)
                    }
                )

                let config: NIOHTTPServerUpgradeConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { context in
                        // Remove HTTP handler after upgrade
                        context.pipeline.removeHandler(name: "HTTPHandler", promise: nil)
                    }
                )

                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: config
                ).flatMap {
                    channel.pipeline.addHandler(
                        HTTPPlaceholderHandler(),
                        name: "HTTPHandler"
                    )
                }
            }

        let ch = try await bootstrap.bind(host: "0.0.0.0", port: port).get()
        self.channel = ch
        logger.info("WebSocket server listening on port \(self.port)")

        // Start heartbeat
        startHeartbeat(on: group.next())

        return stream
    }

    /// Stop the WebSocket server and disconnect all clients.
    func stop() async throws {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        // Close all client connections
        for client in clients.values {
            client.channel.close(promise: nil)
        }
        clients.removeAll()

        try await channel?.close()
        try await group?.shutdownGracefully()
        eventContinuation?.finish()
        eventContinuation = nil
        logger.info("WebSocket server stopped")
    }

    // MARK: - Client Management

    /// Get all currently connected clients.
    func getClients() -> [ConnectedClient] {
        Array(clients.values)
    }

    /// Get all authenticated clients.
    func getAuthenticatedClients() -> [ConnectedClient] {
        clients.values.filter { $0.isAuthenticated }
    }

    /// Get clients subscribed to a specific session.
    func getSubscribers(for sessionId: String) -> [ConnectedClient] {
        clients.values.filter { $0.isSubscribed(to: sessionId) }
    }

    // MARK: - Sending Messages

    /// Send a BalconyMessage to a specific client.
    func send(_ message: BalconyMessage, to client: ConnectedClient) {
        do {
            let data = try encoder.encode(message)

            // If client has crypto set up, encrypt before sending
            if let crypto = client.cryptoManager {
                Task {
                    do {
                        let encrypted = try await crypto.encrypt(data)
                        client.send(encrypted)
                    } catch {
                        logger.error("Encryption failed for client \(client.id): \(error.localizedDescription)")
                    }
                }
            } else {
                // Handshake messages are sent unencrypted
                client.send(data)
            }
        } catch {
            logger.error("Failed to encode message for client \(client.id): \(error.localizedDescription)")
        }
    }

    /// Broadcast a message to all authenticated clients.
    func broadcast(_ message: BalconyMessage) {
        for client in getAuthenticatedClients() {
            send(message, to: client)
        }
    }

    /// Send a message to all clients subscribed to a specific session.
    func sendToSubscribers(of sessionId: String, message: BalconyMessage) {
        for client in getSubscribers(for: sessionId) {
            send(message, to: client)
        }
    }

    // MARK: - Handshake

    /// Process a handshake message from a client.
    private func handleHandshake(from client: ConnectedClient, message: BalconyMessage) {
        do {
            let handshake = try message.decodePayload(HandshakePayload.self)

            // Store device info
            client.deviceInfo = handshake.deviceInfo
            client.state = .authenticated

            // Set up per-client crypto
            let crypto = CryptoManager()
            Task {
                do {
                    let keyPair = try await crypto.generateKeyPair()
                    try await crypto.deriveSharedSecret(theirPublicKey: handshake.publicKey)
                    client.setupCrypto(crypto)

                    // Send handshake acknowledgement with our public key
                    let ack = HandshakeAckPayload(
                        deviceInfo: DeviceInfo(
                            id: getMacDeviceId(),
                            name: Host.current().localizedName ?? "Mac",
                            platform: .macOS,
                            publicKeyFingerprint: keyPair.fingerprint
                        ),
                        publicKey: keyPair.publicKey
                    )
                    let ackMessage = try BalconyMessage.create(type: .handshakeAck, payload: ack)
                    // Send ack unencrypted since client doesn't have our key yet
                    let data = try self.encoder.encode(ackMessage)
                    client.send(data)

                    self.logger.info("Client \(client.id) authenticated: \(handshake.deviceInfo.name)")
                    self.eventContinuation?.yield(.clientAuthenticated(client, handshake.deviceInfo))
                } catch {
                    self.logger.error("Handshake crypto failed for \(client.id): \(error.localizedDescription)")
                    self.sendError(to: client, message: "Handshake failed: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to decode handshake from \(client.id): \(error.localizedDescription)")
            sendError(to: client, message: "Invalid handshake payload")
        }
    }

    // MARK: - Message Handling

    /// Handle a raw data frame from a client, decrypting if needed.
    private func handleRawMessage(from client: ConnectedClient, data: Data) {
        let messageData: Data
        if let crypto = client.cryptoManager {
            // Decrypt incoming message
            Task {
                do {
                    let decrypted = try await crypto.decrypt(data)
                    await self.processMessage(from: client, data: decrypted)
                } catch {
                    self.logger.error("Decryption failed from \(client.id): \(error.localizedDescription)")
                }
            }
            return
        } else {
            // Pre-handshake: messages are plaintext
            messageData = data
        }
        processMessage(from: client, data: messageData)
    }

    private func processMessage(from client: ConnectedClient, data: Data) {
        do {
            let message = try decoder.decode(data)

            switch message.type {
            case .handshake:
                handleHandshake(from: client, message: message)

            case .sessionSubscribe:
                handleSessionSubscribe(from: client, message: message)
                // Also forward to ConnectionManager so it can send session history
                eventContinuation?.yield(.messageReceived(client, message))

            case .sessionUnsubscribe:
                handleSessionUnsubscribe(from: client, message: message)

            case .userInput:
                eventContinuation?.yield(.messageReceived(client, message))

            case .ping:
                // Application-level ping - respond with pong
                if let pong = try? BalconyMessage.create(type: .pong, payload: EmptyPayload()) {
                    send(pong, to: client)
                }

            default:
                eventContinuation?.yield(.messageReceived(client, message))
            }
        } catch {
            logger.error("Failed to decode message from \(client.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Session Subscriptions

    private func handleSessionSubscribe(from client: ConnectedClient, message: BalconyMessage) {
        guard client.isAuthenticated else {
            sendError(to: client, message: "Not authenticated")
            return
        }
        do {
            let payload = try message.decodePayload(SessionSubscribePayload.self)
            client.subscribedSessionIds.insert(payload.sessionId)
            logger.info("Client \(client.id) subscribed to session \(payload.sessionId)")
        } catch {
            logger.error("Invalid subscribe payload from \(client.id): \(error.localizedDescription)")
        }
    }

    private func handleSessionUnsubscribe(from client: ConnectedClient, message: BalconyMessage) {
        do {
            let payload = try message.decodePayload(SessionSubscribePayload.self)
            client.subscribedSessionIds.remove(payload.sessionId)
            logger.info("Client \(client.id) unsubscribed from session \(payload.sessionId)")
        } catch {
            logger.error("Invalid unsubscribe payload from \(client.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(on eventLoop: EventLoop) {
        heartbeatTask = eventLoop.scheduleRepeatedTask(
            initialDelay: .seconds(15),
            delay: .seconds(15)
        ) { [weak self] task in
            guard let self else {
                task.cancel()
                return
            }
            Task { await self.performHeartbeat() }
        }
    }

    private func performHeartbeat() {
        let now = Date()
        let timeout: TimeInterval = 45 // Miss 2 pongs (30s) + buffer

        for client in clients.values {
            if now.timeIntervalSince(client.lastPongAt) > timeout {
                logger.warning("Client \(client.id) heartbeat timeout - disconnecting")
                client.channel.close(promise: nil)
                clientDidDisconnect(client)
            } else {
                client.sendPing()
            }
        }
    }

    // MARK: - Connection Events

    private func clientDidConnect(_ client: ConnectedClient) {
        clients[client.id] = client
        logger.info("Client connected: \(client.id) (total: \(self.clients.count))")
        eventContinuation?.yield(.clientConnected(client))
    }

    private func clientDidDisconnect(_ client: ConnectedClient) {
        guard clients.removeValue(forKey: client.id) != nil else { return }
        client.state = .disconnected
        logger.info("Client disconnected: \(client.id) (total: \(self.clients.count))")
        eventContinuation?.yield(.clientDisconnected(client))
    }

    // MARK: - Helpers

    private func sendError(to client: ConnectedClient, message: String) {
        if let errorMsg = try? BalconyMessage.create(
            type: .error,
            payload: ErrorPayload(message: message)
        ) {
            send(errorMsg, to: client)
        }
    }

    private func getMacDeviceId() -> String {
        // Use a stable identifier based on hardware UUID
        let platformExpert = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        if let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) {
            return (serialNumberAsCFString.takeUnretainedValue() as? String) ?? UUID().uuidString
        }
        return UUID().uuidString
    }
}

// MARK: - HTTP Placeholder Handler

/// Handles HTTP requests before WebSocket upgrade. Returns 426 for non-upgrade requests.
private final class HTTPPlaceholderHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard case .head(let head) = part else { return }

        // Only accept WebSocket upgrade requests
        if !head.headers.contains(name: "Upgrade") {
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/plain")
            headers.add(name: "Connection", value: "close")
            let response = HTTPResponseHead(version: head.version, status: .upgradeRequired, headers: headers)
            context.write(wrapOutboundOut(.head(response)), promise: nil)

            var body = context.channel.allocator.buffer(capacity: 0)
            body.writeString("WebSocket upgrade required")
            context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}

// MARK: - Protocol Payloads

/// Handshake payload sent by iOS client.
struct HandshakePayload: Codable, Sendable {
    let deviceInfo: DeviceInfo
    let publicKey: [UInt8]
}

/// Handshake acknowledgement payload sent by Mac server.
struct HandshakeAckPayload: Codable, Sendable {
    let deviceInfo: DeviceInfo
    let publicKey: [UInt8]
}

/// Error payload.
struct ErrorPayload: Codable, Sendable {
    let message: String
}

/// Empty payload for messages with no body.
struct EmptyPayload: Codable, Sendable {}
