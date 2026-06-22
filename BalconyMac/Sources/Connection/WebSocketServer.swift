import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket
import NIOSSL
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

    /// SHA-256 pin of this server's TLS certificate, surfaced in the handshake ack as the Mac's
    /// device identity. Set in `start()`.
    private var serverCertPin = ""

    init(port: Int = 29170) {
        self.port = port
    }

    // MARK: - Server Lifecycle

    /// Start the WebSocket server (over TLS) and return a stream of server events.
    ///
    /// - Parameters carry the Mac's persisted self-signed certificate + private key (PEM). TLS is
    ///   terminated by NIOSSL at the front of each connection's pipeline; everything downstream
    ///   (HTTP upgrade, WebSocket frames) operates on already-decrypted bytes.
    func start(certPEM: String, keyPEM: String) async throws -> AsyncStream<WebSocketServerEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: WebSocketServerEvent.self)
        self.eventContinuation = continuation

        let sslContext = try TLSIdentity.makeServerContext(certPEM: certPEM, keyPEM: keyPEM)
        self.serverCertPin = try TLSIdentity.pin(forCertPEM: certPEM)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.group = group

        let server = self

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let upgrader = NIOWebSocketServerUpgrader(
                    // The convenience initializer hardcodes a 16 KB max frame size, but iOS
                    // sends input as single unfragmented frames up to 16 MB — a paste/large
                    // input over 16 KB would otherwise trip automatic error handling and tear
                    // the connection down. Allow a generous 1 MB inbound frame.
                    maxFrameSize: 1 << 20,
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
                            onPong: { client in
                                Task { await server.clientDidReceivePong(client) }
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

                // TLS must terminate first, before HTTP parsing sees any bytes.
                let sslHandler = NIOSSLServerHandler(context: sslContext)
                return channel.pipeline.addHandler(sslHandler).flatMap {
                    channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config)
                }.flatMap {
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

    /// Whether any client is currently subscribed to a session.
    func hasSubscribers(for sessionId: String) -> Bool {
        clients.values.contains { $0.isSubscribed(to: sessionId) }
    }

    /// Disconnect a client by its device ID.
    func disconnectClient(deviceId: String) {
        guard let client = clients.values.first(where: { $0.deviceInfo?.id == deviceId }) else {
            logger.debug("No client found for device \(deviceId)")
            return
        }
        logger.info("Disconnecting client: \(deviceId)")
        client.channel.close(promise: nil)
    }

    // MARK: - Sending Messages

    /// Send a BalconyMessage to a specific client.
    func send(_ message: BalconyMessage, to client: ConnectedClient) {
        do {
            let data = try encoder.encode(message)
            // Confidentiality is handled by the TLS transport. Enqueue on the client's serial
            // send chain so concurrent sends can't reorder frames on the wire (which would
            // corrupt the chunked terminal/history stream).
            client.enqueueSend {
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
    ///
    /// The transport is already TLS-encrypted and the client has already pinned this server's
    /// certificate, so the handshake no longer performs key exchange — it just exchanges device
    /// identity and flips the client to `.authenticated`, which the auth gate keys off.
    private func handleHandshake(from client: ConnectedClient, message: BalconyMessage) {
        do {
            let handshake = try message.decodePayload(HandshakePayload.self)

            client.deviceInfo = handshake.deviceInfo
            client.state = .authenticated

            let ack = HandshakeAckPayload(
                deviceInfo: DeviceInfo(
                    id: getMacDeviceId(),
                    name: Host.current().localizedName ?? "Mac",
                    platform: .macOS,
                    certFingerprint: serverCertPin
                )
            )
            let ackMessage = try BalconyMessage.create(type: .handshakeAck, payload: ack)
            client.send(try encoder.encode(ackMessage))

            logger.info("Client \(client.id) authenticated: \(handshake.deviceInfo.name)")
            eventContinuation?.yield(.clientAuthenticated(client, handshake.deviceInfo))
        } catch {
            logger.error("Failed to decode handshake from \(client.id): \(error.localizedDescription)")
            sendError(to: client, message: "Invalid handshake payload")
        }
    }

    // MARK: - Message Handling

    /// Handle a raw data frame from a client. Bytes are already TLS-decrypted by the transport.
    private func handleRawMessage(from client: ConnectedClient, data: Data) {
        processMessage(from: client, data: data)
    }

    private func processMessage(from client: ConnectedClient, data: Data) {
        do {
            let message = try decoder.decode(data)

            // Auth gate: before the handshake completes (and crypto is established) the only
            // message a client may send is the handshake itself. Without this, any device on
            // the LAN could send `.userInput`/`.terminalResize`/picker selections that are
            // forwarded straight into the live Claude Code PTY — blind keystroke injection.
            guard message.type == .handshake || client.isAuthenticated else {
                logger.warning("Dropping \(message.type.rawValue) from unauthenticated client \(client.id)")
                sendError(to: client, message: "Not authenticated")
                return
            }

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

        // Snapshot before iterating: closing a channel drives clientDidDisconnect (which
        // mutates `clients`) via channelInactive, so iterating `clients.values` directly
        // would mutate the collection mid-loop and double-fire the disconnect.
        for client in Array(clients.values) {
            if now.timeIntervalSince(client.lastPongAt) > timeout {
                logger.warning("Client \(client.id) heartbeat timeout - disconnecting")
                client.channel.close(promise: nil) // → channelInactive → clientDidDisconnect
            } else {
                client.sendPing()
            }
        }
    }

    // MARK: - Connection Events

    /// Update pong timestamp on the actor to avoid data race with NIO event loop.
    private func clientDidReceivePong(_ client: ConnectedClient) {
        client.lastPongAt = Date()
    }

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
}

/// Handshake acknowledgement payload sent by Mac server.
struct HandshakeAckPayload: Codable, Sendable {
    let deviceInfo: DeviceInfo
}

/// Error payload.
struct ErrorPayload: Codable, Sendable {
    let message: String
}

/// Empty payload for messages with no body.
struct EmptyPayload: Codable, Sendable {}
