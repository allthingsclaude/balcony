import Foundation
import NIO
import NIOWebSocket
import BalconyShared
import os

// MARK: - Client Connection State

/// Lifecycle state of a connected WebSocket client.
enum ClientState: Sendable {
    case connected
    case authenticated
    case disconnected
}

// MARK: - Connected Client

/// Represents a single connected iOS client with its associated state.
final class ConnectedClient: @unchecked Sendable {
    let id: String
    let channel: Channel
    var deviceInfo: DeviceInfo?
    var state: ClientState = .connected
    var subscribedSessionIds: Set<String> = []
    var lastPongAt: Date = Date()
    private(set) var cryptoManager: CryptoManager?

    init(id: String = UUID().uuidString, channel: Channel) {
        self.id = id
        self.channel = channel
    }

    /// Set up encryption after handshake.
    func setupCrypto(_ crypto: CryptoManager) {
        self.cryptoManager = crypto
    }

    /// Whether this client has completed the handshake.
    var isAuthenticated: Bool {
        state == .authenticated
    }

    /// Whether this client is subscribed to a given session.
    func isSubscribed(to sessionId: String) -> Bool {
        subscribedSessionIds.contains(sessionId)
    }
}

// MARK: - WebSocket Frame Handler

/// NIO channel handler that processes WebSocket frames and bridges to Swift Concurrency.
final class WebSocketFrameHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let logger = Logger(subsystem: "com.balcony.mac", category: "WebSocketFrameHandler")
    private let client: ConnectedClient
    private let onMessage: @Sendable (ConnectedClient, Data) -> Void
    private let onDisconnect: @Sendable (ConnectedClient) -> Void
    private var frameBuffer = ByteBuffer()

    init(
        client: ConnectedClient,
        onMessage: @escaping @Sendable (ConnectedClient, Data) -> Void,
        onDisconnect: @escaping @Sendable (ConnectedClient) -> Void
    ) {
        self.client = client
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        switch frame.opcode {
        case .text, .binary:
            // Collect frame data
            var data = frame.unmaskedData
            let bytes = data.readBytes(length: data.readableBytes) ?? []
            onMessage(client, Data(bytes))

        case .ping:
            // Respond with pong
            let pongFrame = WebSocketFrame(fin: true, opcode: .pong, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(pongFrame), promise: nil)

        case .pong:
            client.lastPongAt = Date()

        case .connectionClose:
            logger.info("Client \(self.client.id) sent close frame")
            // Echo the close frame back
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.data)
            context.writeAndFlush(wrapOutboundOut(closeFrame)).whenComplete { [weak self] _ in
                guard let self else { return }
                context.close(promise: nil)
                self.onDisconnect(self.client)
            }

        case .continuation:
            // Append to buffer for fragmented messages
            var data = frame.unmaskedData
            frameBuffer.writeBuffer(&data)
            if frame.fin {
                let bytes = frameBuffer.readBytes(length: frameBuffer.readableBytes) ?? []
                frameBuffer.clear()
                onMessage(client, Data(bytes))
            }

        default:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        logger.info("Client \(self.client.id) channel inactive")
        onDisconnect(client)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Client \(self.client.id) error: \(error.localizedDescription)")
        context.close(promise: nil)
        onDisconnect(client)
    }
}

// MARK: - Sending Helpers

extension ConnectedClient {
    /// Send a WebSocket binary frame to this client.
    func send(_ data: Data) {
        guard channel.isActive else { return }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let frame = WebSocketFrame(fin: true, opcode: .binary, data: buffer)
        channel.writeAndFlush(frame, promise: nil)
    }

    /// Send a WebSocket ping frame.
    func sendPing() {
        guard channel.isActive else { return }
        let buffer = channel.allocator.buffer(capacity: 0)
        let frame = WebSocketFrame(fin: true, opcode: .ping, data: buffer)
        channel.writeAndFlush(frame, promise: nil)
    }
}
