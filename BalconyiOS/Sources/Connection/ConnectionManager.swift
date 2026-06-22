import Foundation
import UIKit
import Network
import Combine
import BalconyShared
import os

/// Manages discovery, connection, and communication with BalconyMac.
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "ConnectionManager")

    private static let pairedDevicesKey = "com.balcony.pairedDevices"
    private static let lastConnectedDeviceIdKey = "com.balcony.lastConnectedDeviceId"

    @Published var discoveredDevices: [DeviceInfo] = []
    @Published var pairedDevices: [DeviceInfo] = []
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isReconnecting = false
    @Published var isAutoConnecting = false
    @Published var connectionError: String?
    @Published var connectedDevice: DeviceInfo?

    /// Latest BLE RSSI reading in dBm. Updated continuously while scanning.
    @Published var bleRSSI: Int?

    /// Whether the phone has been sustained beyond the away-distance threshold.
    /// Toggles after the signal holds for `awaySustainSeconds`.
    @Published var isPhoneAway: Bool = false

    /// The device ID of the last successfully connected Mac (persisted for auto-reconnect).
    var lastConnectedDeviceId: String? {
        get { UserDefaults.standard.string(forKey: Self.lastConnectedDeviceIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastConnectedDeviceIdKey) }
    }

    private var autoConnectTask: Task<Void, Never>?
    private var reconnectLoopTask: Task<Void, Never>?
    private var rssiCancellable: AnyCancellable?
    private var rssiDisplayCancellable: AnyCancellable?
    private var awayCancellable: AnyCancellable?
    private var lastReportedRSSI: Int?
    private var smoothedRSSI: Double?

    /// Distance threshold in meters beyond which the phone is "away" (matches Mac default).
    private let awayDistanceMeters: Double = 1.0
    /// Seconds the distance signal must sustain before toggling `isPhoneAway`.
    private let awaySustainSeconds: Double = 3.0

    private let bonjourBrowser = BonjourBrowser()
    private let webSocketClient = WebSocketClient()
    private let bleCentral = BLECentral()

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

                    // Auto-connect if this matches the last connected device
                    // (guard against re-triggering if we already tried and failed)
                    if !self.isConnected && !self.isConnecting && !self.isAutoConnecting,
                       self.autoConnectTask == nil,
                       let lastId = self.lastConnectedDeviceId,
                       deviceInfo.id == lastId {
                        self.attemptAutoConnect(to: deviceInfo)
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
                    await self?.handleUnexpectedDisconnect(unexpected: unexpected)
                }
            }

            // The cert pin (captured at QR pairing) authenticates the server. A Bonjour-discovered
            // device carries no pin of its own, so fall back to the pin saved when this Mac was
            // paired via QR — matched by the Mac's stable device id (`did`), which both the QR
            // pairing record and the Bonjour advertisement key off. No pin → require QR first.
            let pin = device.certFingerprint.isEmpty
                ? (pairedDevices.first { $0.id == device.id }?.certFingerprint ?? "")
                : device.certFingerprint
            guard !pin.isEmpty else {
                logger.error("No certificate pin for \(device.name); QR pairing required")
                isConnecting = false
                connectionError = "Pair with \(device.name) by scanning its QR code first."
                return
            }
            await webSocketClient.setPin(pin)

            // Persist the resolved pin onto the record so it stays connectable on its own.
            let pairedDevice = DeviceInfo(
                id: device.id,
                name: device.name,
                platform: device.platform,
                certFingerprint: pin
            )

            // Connect WebSocket (the TLS handshake enforces the cert pin)
            try await webSocketClient.connect(host: host, port: port)

            // Exchange device identity
            try await performHandshake(with: pairedDevice)

            isConnected = true
            isConnecting = false
            isReconnecting = false
            isAutoConnecting = false
            connectedDevice = pairedDevice
            savePairedDevice(pairedDevice)
            lastConnectedDeviceId = pairedDevice.id
            startRSSIReporting()
            logger.info("Connected to \(device.name)")
        } catch {
            logger.error("Connection failed: \(error.localizedDescription)")
            isConnecting = false
            isConnected = false
            isReconnecting = false
            isAutoConnecting = false
            connectedDevice = nil
            connectionError = "Failed to connect to \(device.name). Make sure BalconyMac is running."
        }
    }

    /// Connect directly using host/port + certificate pin from a QR code scan.
    func connectDirect(host: String, port: Int, certFingerprint: String?) async {
        logger.info("Direct connect to \(host):\(port)")
        isConnecting = true
        connectionError = nil

        let device = DeviceInfo(
            id: "\(host):\(port)",
            name: host,
            platform: .macOS,
            certFingerprint: certFingerprint ?? ""
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
                    await self?.handleUnexpectedDisconnect(unexpected: unexpected)
                }
            }

            guard !device.certFingerprint.isEmpty else {
                logger.error("QR code missing certificate pin")
                isConnecting = false
                connectionError = "This QR code is missing security info. Regenerate it on your Mac."
                return
            }
            await webSocketClient.setPin(device.certFingerprint)

            // Connect WebSocket (the TLS handshake enforces the cert pin)
            try await webSocketClient.connect(host: host, port: port)

            // Exchange device identity; the ack carries the Mac's stable device id.
            let macInfo = try await performHandshake(with: device)

            // Key the paired record by the Mac's stable id so Bonjour discovery can later match it
            // and reconnect without re-scanning the QR.
            let pairedDevice = DeviceInfo(
                id: macInfo.id,
                name: macInfo.name,
                platform: .macOS,
                certFingerprint: device.certFingerprint
            )

            isConnected = true
            isConnecting = false
            isReconnecting = false
            isAutoConnecting = false
            connectedDevice = pairedDevice
            savePairedDevice(pairedDevice)
            lastConnectedDeviceId = pairedDevice.id
            startRSSIReporting()
            logger.info("Connected to \(macInfo.name) via QR")
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
        autoConnectTask?.cancel()
        autoConnectTask = nil
        reconnectLoopTask?.cancel()
        reconnectLoopTask = nil
        stopRSSIReporting()
        await webSocketClient.disconnect()
        isConnected = false
        isReconnecting = false
        isAutoConnecting = false
        connectedDevice = nil
        lastConnectedDeviceId = nil
        logger.info("Disconnected")
    }

    /// Cancel an in-progress auto-connect attempt.
    func cancelAutoConnect() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        isAutoConnecting = false
        isConnecting = false
        logger.info("Auto-connect cancelled")
    }

    /// Attempt to auto-connect to a previously connected device (30s timeout).
    private func attemptAutoConnect(to device: DeviceInfo) {
        logger.info("Auto-connecting to \(device.name)")
        isAutoConnecting = true
        autoConnectTask = Task { [weak self] in
            // Race the connection against a 30-second timeout
            let connected = await withTaskGroup(of: Bool.self) { group in
                group.addTask { @MainActor [weak self] in
                    await self?.connect(to: device)
                    return self?.isConnected ?? false
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    return false
                }
                let result = await group.next() ?? false
                group.cancelAll()
                return result
            }

            guard let self, !Task.isCancelled else { return }
            if !connected {
                self.isAutoConnecting = false
                self.isConnecting = false
                // Don't show error alert for auto-connect — it wasn't user-initiated
                self.connectionError = nil
                self.autoConnectTask = nil
                self.logger.info("Auto-connect failed for \(device.name)")
            }
        }
    }

    // MARK: - Session Reconnection

    /// Handle a dropped WebSocket. The transport layer cannot restore the E2E
    /// session (a fresh handshake is required), so we stop its socket-level
    /// retries and run a full reconnect loop at this layer instead.
    private func handleUnexpectedDisconnect(unexpected: Bool) async {
        isConnected = false
        guard unexpected else { return }
        // Set before any suspension point so the UI observes the drop and the
        // reconnecting state together (otherwise it routes to discovery).
        isReconnecting = true
        logger.warning("Connection lost unexpectedly — starting session reconnect")
        await webSocketClient.disconnect() // stop transport-level retries
        startSessionReconnect()
    }

    /// Full reconnect loop (handshake included) with exponential backoff.
    /// Gives up after a few attempts, clearing `isReconnecting` so the UI can
    /// fall back to discovery (where Bonjour auto-connect takes over).
    private func startSessionReconnect() {
        guard reconnectLoopTask == nil else { return }
        guard let device = connectedDevice else {
            isReconnecting = false
            return
        }
        isReconnecting = true
        reconnectLoopTask = Task { [weak self] in
            defer { self?.reconnectLoopTask = nil }
            for attempt in 1...5 {
                let delay = min(pow(2.0, Double(attempt - 1)), 8.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled, !self.isConnected else { return }
                self.logger.info("Session reconnect attempt \(attempt)/5")
                await self.attemptFullReconnect(to: device)
                if self.isConnected { return }
                // connect() clears these on failure — restore so the banner's
                // retry affordance and reconnecting state survive the loop.
                self.connectedDevice = device
                self.connectionError = nil
                self.isReconnecting = true
            }
            guard let self, !self.isConnected else { return }
            self.logger.warning("Session reconnect gave up after 5 attempts")
            self.isReconnecting = false
        }
    }

    /// User-initiated reconnect to the device whose connection dropped.
    /// Keeps `connectedDevice` on failure so the retry affordance survives.
    func reconnectNow() async {
        guard !isConnected, !isConnecting, let device = connectedDevice else { return }
        logger.info("Manual reconnect to \(device.name)")
        // Take over from the automatic loop.
        reconnectLoopTask?.cancel()
        reconnectLoopTask = nil
        await attemptFullReconnect(to: device)
        if !isConnected {
            connectedDevice = device
            connectionError = nil // banner communicates the state; no alert
            isReconnecting = false // show "Connection lost" + Retry, not a spinner
        }
    }

    /// One full reconnect attempt via the appropriate path for the device.
    private func attemptFullReconnect(to device: DeviceInfo) async {
        if discoveredEndpoints[device.id] != nil {
            await connect(to: device)
        } else if let colon = device.id.lastIndex(of: ":"),
                  let port = Int(device.id[device.id.index(after: colon)...]) {
            // QR-paired device ids are "host:port"; reuse the saved cert pin.
            await connectDirect(host: String(device.id[..<colon]), port: port, certFingerprint: device.certFingerprint)
        } else {
            // Bonjour endpoint not currently known — restart discovery so the
            // device reappears; the next loop attempt may find it.
            startDiscovery()
        }
    }

    /// Send a message to the connected Mac.
    func send(_ message: BalconyMessage) async throws {
        try await webSocketClient.send(message)
    }

    // MARK: - RSSI Reporting

    /// Start observing BLE RSSI and forwarding to Mac, debounced every 5 seconds.
    private func startRSSIReporting() {
        lastReportedRSSI = nil

        // Update published property for UI with exponential moving average to smooth jitter
        smoothedRSSI = nil
        rssiDisplayCancellable = bleCentral.$rssi
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, let raw = value else {
                    self?.bleRSSI = value
                    return
                }
                let isFirst = self.smoothedRSSI == nil
                if let prev = self.smoothedRSSI {
                    // EMA: alpha=0.3 weights new readings but dampens spikes
                    self.smoothedRSSI = 0.3 * Double(raw) + 0.7 * prev
                } else {
                    self.smoothedRSSI = Double(raw)
                }
                self.bleRSSI = Int(self.smoothedRSSI!.rounded())
                // Set initial away state immediately on first reading (skip debounce)
                if isFirst {
                    self.isPhoneAway = Self.estimatedDistance(for: Int(self.smoothedRSSI!.rounded())) > self.awayDistanceMeters
                }
            }

        // Track sustained away/present using smoothed RSSI for auto-notification toggle
        awayCancellable = $bleRSSI
            .compactMap { $0 }
            .map { [weak self] rssi -> Bool in
                guard let self else { return false }
                let distance = Self.estimatedDistance(for: rssi)
                return distance > self.awayDistanceMeters
            }
            .removeDuplicates()
            .debounce(for: .seconds(awaySustainSeconds), scheduler: DispatchQueue.main)
            .sink { [weak self] away in
                self?.isPhoneAway = away
            }

        // Send debounced reports to Mac
        rssiCancellable = bleCentral.$rssi
            .compactMap { $0 }
            .removeDuplicates()
            .debounce(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] rssi in
                guard let self, self.isConnected else { return }
                // Only send if value changed significantly (≥5 dBm)
                if let last = self.lastReportedRSSI, abs(rssi - last) < 5 { return }
                self.lastReportedRSSI = rssi
                Task {
                    do {
                        let payload = BLERSSIReportPayload(rssi: rssi)
                        let msg = try BalconyMessage.create(type: .bleRSSIReport, payload: payload)
                        try await self.send(msg)
                    } catch {
                        self.logger.error("Failed to send RSSI report: \(error.localizedDescription)")
                    }
                }
            }
    }

    /// Stop RSSI reporting.
    private func stopRSSIReporting() {
        rssiCancellable?.cancel()
        rssiCancellable = nil
        rssiDisplayCancellable?.cancel()
        rssiDisplayCancellable = nil
        awayCancellable?.cancel()
        awayCancellable = nil
        lastReportedRSSI = nil
        smoothedRSSI = nil
        bleRSSI = nil
        isPhoneAway = false
    }

    /// Estimate distance in meters from a BLE RSSI value using log-distance path loss model.
    static func estimatedDistance(for rssi: Int) -> Double {
        let measuredPower = -59.0 // Typical BLE RSSI at 1 meter
        let n = 2.5 // Indoor path-loss exponent
        return pow(10.0, (measuredPower - Double(rssi)) / (10.0 * n))
    }

    // MARK: - Endpoint Resolution

    /// Resolve a Bonjour NWEndpoint to a concrete host and port, with a timeout.
    private func resolveEndpoint(_ endpoint: NWEndpoint) async -> (String, Int)? {
        await withTaskGroup(of: (String, Int)?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let connection = NWConnection(to: endpoint, using: .tcp)
                    connection.stateUpdateHandler = { [weak connection] state in
                        switch state {
                        case .ready:
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
                                let hostString = String(rawHost.prefix(while: { $0 != "%" }))
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

            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s timeout
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Handshake

    /// Exchange device identity with the Mac server over the (already pinned + TLS-encrypted)
    /// connection. No key exchange — confidentiality and server authentication are handled by the
    /// TLS transport and the certificate pin. Returns the Mac's identity (from the ack), whose
    /// `id` is the stable device id used to key the paired record.
    @discardableResult
    private func performHandshake(with device: DeviceInfo) async throws -> DeviceInfo {
        let ourDeviceInfo = DeviceInfo(
            id: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            name: UIDevice.current.name,
            platform: .iOS,
            certFingerprint: ""
        )

        let handshake = HandshakePayload(deviceInfo: ourDeviceInfo)
        let handshakeMessage = try BalconyMessage.create(type: .handshake, payload: handshake)
        try await webSocketClient.send(handshakeMessage)

        // Wait for handshake acknowledgement
        let ackMessage = try await waitForMessage(ofType: .handshakeAck, timeout: 10.0)
        let ack = try ackMessage.decodePayload(HandshakeAckPayload.self)

        logger.info("Handshake complete with \(ack.deviceInfo.name)")

        // Re-request the session list: the initial list the Mac sends on authentication can
        // arrive while waitForMessage has temporarily swapped the message handler, so re-request
        // to be sure the UI gets it.
        let requestMsg = try BalconyMessage.create(type: .sessionList, payload: EmptyPayload())
        try await webSocketClient.send(requestMsg)

        return ack.deviceInfo
    }

    /// Minimal mirror of the Mac server's error payload, for decoding handshake failures.
    private struct ServerErrorPayload: Decodable { let message: String }

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
                        } else if message.type == .error {
                            // The Mac emits .error on handshake/auth failure; surface it
                            // immediately instead of waiting out the timeout.
                            self?.onMessage = previousHandler
                            let reason = (try? message.decodePayload(ServerErrorPayload.self).message)
                                ?? "Server rejected the connection"
                            continuation.resume(throwing: BalconyError.connectionFailed(reason))
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
        // Stop silently auto-reconnecting to a device the user just removed.
        if lastConnectedDeviceId == device.id {
            lastConnectedDeviceId = nil
        }
        if connectedDevice?.id == device.id {
            Task { await disconnect() }
        }
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
}

/// Handshake acknowledgement payload sent by Mac server.
struct HandshakeAckPayload: Codable, Sendable {
    let deviceInfo: DeviceInfo
}
