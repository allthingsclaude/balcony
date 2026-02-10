import Foundation
import UIKit
import Network
import BalconyShared
import os

/// Manages discovery, connection, and communication with BalconyMac.
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "ConnectionManager")

    private static let pairedDevicesKey = "com.balcony.pairedDevices"

    @Published var discoveredDevices: [DeviceInfo] = []
    @Published var pairedDevices: [DeviceInfo] = []
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isReconnecting = false
    @Published var connectionError: String?
    @Published var connectedDevice: DeviceInfo?

    private let bonjourBrowser = BonjourBrowser()
    private let webSocketClient = WebSocketClient()
    private let bleCentral = BLECentral()
    private let cryptoManager = CryptoManager()

    /// Maps device IDs to their resolved NWEndpoints for connection.
    private var discoveredEndpoints: [String: NWEndpoint] = [:]

    /// Receive callback for incoming messages.
    var onMessage: ((BalconyMessage) -> Void)?

    init() {
        loadPairedDevices()
    }

    // MARK: - Discovery

    /// Start discovering nearby Macs.
    func startDiscovery() {
        Task {
            await bonjourBrowser.setOnDeviceFound { [weak self] deviceInfo, endpoint in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.discoveredEndpoints[deviceInfo.id] = endpoint
                    if !self.discoveredDevices.contains(where: { $0.id == deviceInfo.id }) {
                        self.discoveredDevices.append(deviceInfo)
                        self.logger.info("Discovered device: \(deviceInfo.name)")
                    }
                }
            }
            await bonjourBrowser.setOnDeviceLost { [weak self] deviceId in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.discoveredDevices.removeAll { $0.id == deviceId }
                    self.discoveredEndpoints.removeValue(forKey: deviceId)
                    self.logger.info("Lost device: \(deviceId)")
                }
            }
            await bonjourBrowser.startBrowsing()
        }
        bleCentral.startScanning()
        logger.info("Discovery started")
    }

    /// Stop discovery.
    func stopDiscovery() {
        Task {
            await bonjourBrowser.stopBrowsing()
        }
        bleCentral.stopScanning()
        logger.info("Discovery stopped")
    }

    // MARK: - Connection

    /// Connect to a discovered Mac.
    func connect(to device: DeviceInfo) async {
        logger.info("Connecting to \(device.name)")
        isConnecting = true
        connectionError = nil

        guard let endpoint = discoveredEndpoints[device.id] else {
            logger.error("No endpoint found for device \(device.id)")
            isConnecting = false
            connectionError = "Could not find \(device.name) on the network."
            return
        }

        // Resolve the Bonjour endpoint to a host and port
        guard let (host, port) = await resolveEndpoint(endpoint) else {
            logger.error("Failed to resolve endpoint for \(device.name)")
            isConnecting = false
            connectionError = "Could not resolve address for \(device.name)."
            return
        }

        do {
            // Set up message receive handler
            await webSocketClient.setOnMessage { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.handleMessage(message)
                }
            }

            // Set up disconnect handler
            await webSocketClient.setOnDisconnect { [weak self] unexpected in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isConnected = false
                    if unexpected {
                        self.isReconnecting = true
                        self.logger.warning("Connection lost unexpectedly, WebSocket will auto-reconnect")
                    }
                }
            }

            // Connect WebSocket
            try await webSocketClient.connect(host: host, port: port)

            // Perform E2E handshake
            try await performHandshake(with: device)

            isConnected = true
            isConnecting = false
            isReconnecting = false
            connectedDevice = device
            savePairedDevice(device)
            logger.info("Connected to \(device.name)")
        } catch {
            logger.error("Connection failed: \(error.localizedDescription)")
            isConnecting = false
            isConnected = false
            isReconnecting = false
            connectedDevice = nil
            connectionError = "Failed to connect to \(device.name). Make sure BalconyMac is running."
        }
    }

    /// Connect directly using host/port from QR code scan.
    func connectDirect(host: String, port: Int, publicKeyBase64: String?) async {
        logger.info("Direct connect to \(host):\(port)")
        isConnecting = true
        connectionError = nil

        let device = DeviceInfo(
            id: "\(host):\(port)",
            name: host,
            platform: .macOS,
            publicKeyFingerprint: publicKeyBase64 ?? ""
        )

        do {
            // Set up message receive handler
            await webSocketClient.setOnMessage { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.handleMessage(message)
                }
            }

            // Set up disconnect handler
            await webSocketClient.setOnDisconnect { [weak self] unexpected in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isConnected = false
                    if unexpected {
                        self.isReconnecting = true
                        self.logger.warning("Connection lost unexpectedly, WebSocket will auto-reconnect")
                    }
                }
            }

            // Connect WebSocket
            try await webSocketClient.connect(host: host, port: port)

            // Perform E2E handshake
            try await performHandshake(with: device)

            isConnected = true
            isConnecting = false
            isReconnecting = false
            connectedDevice = device
            savePairedDevice(device)
            logger.info("Connected to \(host):\(port) via QR")
        } catch {
            logger.error("Direct connection failed: \(error.localizedDescription)")
            isConnecting = false
            isConnected = false
            isReconnecting = false
            connectedDevice = nil
            connectionError = "Failed to connect to \(host):\(port). Check the address and try again."
        }
    }

    /// Disconnect from current Mac.
    func disconnect() async {
        await webSocketClient.disconnect()
        isConnected = false
        isReconnecting = false
        connectedDevice = nil
        logger.info("Disconnected")
    }

    /// Send a message to the connected Mac.
    func send(_ message: BalconyMessage) async throws {
        try await webSocketClient.send(message)
    }

    // MARK: - Endpoint Resolution

    /// Resolve a Bonjour NWEndpoint to a concrete host and port.
    private func resolveEndpoint(_ endpoint: NWEndpoint) async -> (String, Int)? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    // Extract the resolved host and port from the current path
                    if let innerEndpoint = connection?.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = innerEndpoint {
                        let rawHost: String
                        switch host {
                        case .ipv4(let addr):
                            rawHost = "\(addr)"
                        case .ipv6(let addr):
                            rawHost = "\(addr)"
                        case .name(let name, _):
                            rawHost = name
                        @unknown default:
                            rawHost = "\(host)"
                        }
                        // Strip interface scope suffix (e.g. "%en0") that breaks URLs
                        let hostString = String(rawHost.prefix(while: { $0 != "%" }))
                        // Prevent .cancelled from resuming again
                        connection?.stateUpdateHandler = nil
                        connection?.cancel()
                        continuation.resume(returning: (hostString, Int(port.rawValue)))
                    } else {
                        connection?.stateUpdateHandler = nil
                        connection?.cancel()
                        continuation.resume(returning: nil)
                    }
                case .failed:
                    connection?.stateUpdateHandler = nil
                    connection?.cancel()
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    // MARK: - Handshake

    /// Perform the E2E encrypted handshake with the Mac server.
    private func performHandshake(with device: DeviceInfo) async throws {
        // Generate our key pair
        let keyPair = try await cryptoManager.generateKeyPair()

        // Build our device info
        let ourDeviceInfo = DeviceInfo(
            id: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            name: UIDevice.current.name,
            platform: .iOS,
            publicKeyFingerprint: keyPair.fingerprint
        )

        // Send handshake with our public key
        let handshake = HandshakePayload(
            deviceInfo: ourDeviceInfo,
            publicKey: keyPair.publicKey
        )
        let handshakeMessage = try BalconyMessage.create(type: .handshake, payload: handshake)
        try await webSocketClient.send(handshakeMessage)

        // Wait for handshake acknowledgement
        let ackMessage = try await waitForMessage(ofType: .handshakeAck, timeout: 10.0)
        let ack = try ackMessage.decodePayload(HandshakeAckPayload.self)

        // Derive shared secret from server's public key
        try await cryptoManager.deriveSharedSecret(theirPublicKey: ack.publicKey)

        // Enable encryption on the WebSocket transport
        await webSocketClient.setCrypto(cryptoManager)

        logger.info("Handshake complete with \(ack.deviceInfo.name)")

        // Request session list now that crypto is ready (the initial list
        // sent by the Mac during authentication arrives before setCrypto
        // and gets dropped, so we re-request here)
        let requestMsg = try BalconyMessage.create(type: .sessionList, payload: EmptyPayload())
        try await webSocketClient.send(requestMsg)
    }

    /// Wait for a specific message type with timeout.
    private func waitForMessage(ofType type: MessageType, timeout: TimeInterval) async throws -> BalconyMessage {
        try await withThrowingTaskGroup(of: BalconyMessage.self) { group in
            group.addTask { @MainActor [weak self] in
                // Poll for the expected message via a continuation
                try await withCheckedThrowingContinuation { continuation in
                    let previousHandler = self?.onMessage
                    self?.onMessage = { message in
                        if message.type == type {
                            self?.onMessage = previousHandler
                            continuation.resume(returning: message)
                        } else {
                            previousHandler?(message)
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw BalconyError.connectionFailed("Handshake timed out after \(timeout)s")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: BalconyMessage) {
        onMessage?(message)
    }

    // MARK: - Device Persistence

    private func loadPairedDevices() {
        guard let data = UserDefaults.standard.data(forKey: Self.pairedDevicesKey) else { return }
        do {
            let decoder = JSONDecoder()
            pairedDevices = try decoder.decode([DeviceInfo].self, from: data)
            logger.info("Loaded \(self.pairedDevices.count) paired devices")
        } catch {
            logger.error("Failed to load paired devices: \(error.localizedDescription)")
        }
    }

    private func savePairedDevice(_ device: DeviceInfo) {
        if !pairedDevices.contains(where: { $0.id == device.id }) {
            pairedDevices.append(device)
        }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pairedDevices)
            UserDefaults.standard.set(data, forKey: Self.pairedDevicesKey)
        } catch {
            logger.error("Failed to save paired devices: \(error.localizedDescription)")
        }
    }

    /// Remove a paired device.
    func removePairedDevice(_ device: DeviceInfo) {
        pairedDevices.removeAll { $0.id == device.id }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(pairedDevices)
            UserDefaults.standard.set(data, forKey: Self.pairedDevicesKey)
        } catch {
            logger.error("Failed to save paired devices after removal: \(error.localizedDescription)")
        }
    }
}

// MARK: - Handshake Payloads (must match Mac-side definitions)

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
