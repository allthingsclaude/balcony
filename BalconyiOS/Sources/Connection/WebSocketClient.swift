import Foundation
import BalconyShared
import Security
import os

/// URLSession delegate that authenticates the Mac by pinning its self-signed certificate.
///
/// Because the client dials a raw IP (the Bonjour endpoint is resolved before connecting), there
/// is no usable hostname/SAN and no CA chain — so trust evaluation is taken over entirely and the
/// server is accepted **only** if the leaf certificate's SHA-256 (the `pin`) matches the value
/// captured from the pairing QR. Any other outcome cancels the connection (never falls back to
/// default handling, which would silently fail differently). This is what prevents MITM on the LAN.
private final class PinningDelegate: NSObject, URLSessionDelegate, Sendable {
    private let expectedPin: String?

    init(expectedPin: String?) {
        self.expectedPin = expectedPin
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let expectedPin,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let der = SecCertificateCopyData(leaf) as Data
        // Same canonical pin definition the Mac uses for the QR: SHA-256 of the leaf cert DER.
        if TLSIdentity.pin(forCertDER: Array(der)) == expectedPin {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

/// WebSocket client for connecting to BalconyMac.
actor WebSocketClient {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "WebSocketClient")

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private(set) var isConnected = false

    // MARK: - Certificate pinning

    /// Expected SHA-256 pin of the Mac's TLS certificate (from QR pairing). Must be set before
    /// `connect`; the TLS handshake is rejected if the server's cert doesn't match.
    private var expectedPin: String?

    /// Set the certificate pin to enforce on the next connection.
    func setPin(_ pin: String?) {
        self.expectedPin = pin
    }

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
        // Confidentiality is handled by the TLS (wss) transport.
        try await task.send(.data(data))
    }

    // MARK: - Internal Connection

    private func establishConnection(host: String, port: Int) async throws {
        // Clean up previous connection if any
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()

        // wss:// — confidentiality via TLS; the server is authenticated by pinning its
        // self-signed certificate (PinningDelegate) against the pin captured at QR pairing.
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = port
        components.path = "/ws"
        guard let url = components.url else {
            throw BalconyError.connectionFailed("Invalid URL for host: \(host):\(port)")
        }
        let config = URLSessionConfiguration.default
        let delegate = PinningDelegate(expectedPin: expectedPin)
        let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let task = urlSession.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024 // 16 MB (default 1 MB is too small for session history)
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
        let decoder = MessageDecoder()

        do {
            while isConnected {
                let message = try await task.receive()
                let rawData: Data

                switch message {
                case .data(let data):
                    rawData = data
                case .string(let string):
                    guard let data = string.data(using: .utf8) else { continue }
                    rawData = data
                @unknown default:
                    continue
                }

                // Bytes are already TLS-decrypted by the transport.
                if let decoded = try? decoder.decode(rawData) {
                    onMessage?(decoded)
                } else {
                    logger.warning("Failed to decode message (\(rawData.count) bytes)")
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
