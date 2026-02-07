import Foundation
import BalconyShared
import os

/// WebSocket client for connecting to BalconyMac.
actor WebSocketClient {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "WebSocketClient")
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false

    /// Message receive callback.
    private var onMessage: (@Sendable (BalconyMessage) -> Void)?

    /// Set the callback for received messages.
    func setOnMessage(_ handler: @escaping @Sendable (BalconyMessage) -> Void) {
        onMessage = handler
    }

    /// Connect to a BalconyMac WebSocket server.
    func connect(host: String, port: Int) async throws {
        let url = URL(string: "wss://\(host):\(port)/ws")!
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        // Trust self-signed certificates for local connections
        task.resume()

        self.session = session
        self.webSocketTask = task
        self.isConnected = true

        logger.info("Connected to \(host):\(port)")

        // Start receive loop
        Task {
            await receiveLoop()
        }
    }

    /// Disconnect from the server.
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session = nil
        isConnected = false
        logger.info("Disconnected")
    }

    /// Send a message to the server.
    func send(_ message: BalconyMessage) async throws {
        let encoder = MessageEncoder()
        let data = try encoder.encode(message)
        try await webSocketTask?.send(.data(data))
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        do {
            while isConnected {
                let message = try await task.receive()
                switch message {
                case .data(let data):
                    let decoder = MessageDecoder()
                    if let decoded = try? decoder.decode(data) {
                        onMessage?(decoded)
                    }
                case .string(let string):
                    let decoder = MessageDecoder()
                    if let decoded = try? decoder.decode(string) {
                        onMessage?(decoded)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            logger.error("Receive error: \(error.localizedDescription)")
            isConnected = false
            // TODO: Trigger reconnection with exponential backoff
        }
    }
}
