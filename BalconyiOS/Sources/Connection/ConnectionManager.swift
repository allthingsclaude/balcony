import Foundation
import BalconyShared
import os

/// Manages discovery, connection, and communication with BalconyMac.
@MainActor
final class ConnectionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "ConnectionManager")

    @Published var discoveredDevices: [DeviceInfo] = []
    @Published var pairedDevices: [DeviceInfo] = []
    @Published var isConnected = false
    @Published var connectedDevice: DeviceInfo?

    private let bonjourBrowser = BonjourBrowser()
    private let webSocketClient = WebSocketClient()
    private let bleCentral = BLECentral()
    private let cryptoManager = CryptoManager()

    /// Start discovering nearby Macs.
    func startDiscovery() {
        Task {
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

    /// Connect to a discovered Mac.
    func connect(to device: DeviceInfo) async {
        logger.info("Connecting to \(device.name)")
        // TODO: Resolve Bonjour endpoint to host/port
        // TODO: Establish WebSocket connection
        // TODO: Perform encrypted handshake
        isConnected = true
        connectedDevice = device
    }

    /// Disconnect from current Mac.
    func disconnect() async {
        await webSocketClient.disconnect()
        isConnected = false
        connectedDevice = nil
        logger.info("Disconnected")
    }
}
