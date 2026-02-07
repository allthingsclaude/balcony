import Foundation
import BalconyShared
import os

/// Coordinates all connection components (WebSocket, Bonjour, BLE).
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "ConnectionManager")

    @Published var connectedDevices: [DeviceInfo] = []
    @Published var isServerRunning = false

    private let webSocketServer: WebSocketServer
    private let bonjourAdvertiser: BonjourAdvertiser
    private let blePeripheral: BLEPeripheral
    private let cryptoManager: CryptoManager

    init(
        port: Int = 29170
    ) {
        self.webSocketServer = WebSocketServer(port: port)
        self.bonjourAdvertiser = BonjourAdvertiser(port: UInt16(port))
        self.blePeripheral = BLEPeripheral()
        self.cryptoManager = CryptoManager()
    }

    /// Start all connection services.
    func start() async throws {
        logger.info("Starting connection services")

        // Generate encryption keys
        let keyPair = try await cryptoManager.generateKeyPair()
        let fingerprint = keyPair.fingerprint

        // Start WebSocket server
        try await webSocketServer.start()

        // Start Bonjour advertising
        try await bonjourAdvertiser.startAdvertising(publicKeyFingerprint: fingerprint)

        // Start BLE peripheral
        blePeripheral.startAdvertising(deviceName: Host.current().localizedName ?? "Mac")

        isServerRunning = true
        logger.info("All connection services started")
    }

    /// Stop all connection services.
    func stop() async throws {
        try await webSocketServer.stop()
        await bonjourAdvertiser.stopAdvertising()
        blePeripheral.stopAdvertising()
        isServerRunning = false
        logger.info("All connection services stopped")
    }
}
