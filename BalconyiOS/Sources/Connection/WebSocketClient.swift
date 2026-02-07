import Foundation
import BalconyShared
import os

/// URLSession delegate that trusts self-signed certificates for local connections.
private final class LocalTLSDelegate: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Trust self-signed certificates for local network connections
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

/// WebSocket client for connecting to BalconyMac.
actor WebSocketClient {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "WebSocketClient")
    private let tlsDelegate = LocalTLSDelegate()

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private(set) var isConnected = false

    // MARK: - Reconnection State

    private var currentHost: String?
    private var currentPort: Int?
    private var reconnectAttempt = 0
    private var isReconnecting = false
    private var reconnectTask: Task<Void, Never>?

    private let maxReconnectAttempts = 8
    private let maxBackoffSeconds: Double = 30

    // MARK: - Callbacks

    /// Message receive callback.
    private var onMessage: (@Sendable (BalconyMessage) -> Void)?
    /// Disconnect callback (passes `true` if unexpected, i.e. should reconnect).
    private var onDisconnect: (@Sendable (Bool) -> Void)?

    /// Set the callback for received messages.
    func setOnMessage(_ handler: @escaping @Sendable (BalconyMessage) -> Void) {
        onMessage = handler
    }

    /// Set the callback for disconnection events.
    func setOnDisconnect(_ handler: @escaping @Sendable (Bool) -> Void) {
        onDisconnect = handler
    }

    // MARK: - Connection

    /// Connect to a BalconyMac WebSocket server.
    func connect(host: String, port: Int) async throws {
        currentHost = host
        currentPort = port
        reconnectAttempt = 0
        isReconnecting = false
        reconnectTask?.cancel()
        reconnectTask = nil

        try await establishConnection(host: host, port: port)
    }

    /// Disconnect from the server. Does not trigger auto-reconnect.
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false
        reconnectAttempt = 0
        currentHost = nil
        currentPort = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
        logger.info("Disconnected")
    }

    /// Send a message to the server.
    func send(_ message: BalconyMessage) async throws {
        guard isConnected, let task = webSocketTask else {
            throw BalconyError.connectionFailed("Not connected")
        }
        let encoder = MessageEncoder()
        let data = try encoder.encode(message)
        try await task.send(.data(data))
    }

    // MARK: - Internal Connection

    private func establishConnection(host: String, port: Int) async throws {
        // Clean up previous connection if any
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()

        let url = URL(string: "wss://\(host):\(port)/ws")!
        let config = URLSessionConfiguration.default
        let urlSession = URLSession(configuration: config, delegate: tlsDelegate, delegateQueue: nil)
        let task = urlSession.webSocketTask(with: url)
        task.resume()

        self.session = urlSession
        self.webSocketTask = task
        self.isConnected = true

        logger.info("Connected to \(host):\(port)")

        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    // MARK: - Receive Loop

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
            guard isConnected else { return } // Clean disconnect, ignore error
            logger.error("Receive error: \(error.localizedDescription)")
            isConnected = false
            onDisconnect?(true)
            scheduleReconnect()
        }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard !isReconnecting,
              reconnectAttempt < maxReconnectAttempts,
              let host = currentHost,
              let port = currentPort else {
            if reconnectAttempt >= maxReconnectAttempts {
                logger.warning("Max reconnect attempts (\(self.maxReconnectAttempts)) reached, giving up")
                onDisconnect?(true)
            }
            return
        }

        isReconnecting = true
        reconnectAttempt += 1

        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), maxBackoffSeconds)
        logger.info("Reconnecting in \(delay)s (attempt \(self.reconnectAttempt)/\(self.maxReconnectAttempts))")

        reconnectTask = Task { [weak self, reconnectAttempt] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return // Cancelled
            }

            guard let self else { return }
            await self.attemptReconnect(host: host, port: port, attempt: reconnectAttempt)
        }
    }

    private func attemptReconnect(host: String, port: Int, attempt: Int) async {
        // Guard against stale reconnect tasks
        guard isReconnecting, reconnectAttempt == attempt else { return }

        do {
            try await establishConnection(host: host, port: port)
            reconnectAttempt = 0
            isReconnecting = false
            logger.info("Reconnected successfully")
        } catch {
            logger.error("Reconnect attempt \(attempt) failed: \(error.localizedDescription)")
            isReconnecting = false
            scheduleReconnect()
        }
    }
}
