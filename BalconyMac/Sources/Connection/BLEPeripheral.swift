import Foundation
import CoreBluetooth
import os

/// BLE Peripheral for proximity detection by iOS clients.
final class BLEPeripheral: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "BLEPeripheral")
    private var peripheralManager: CBPeripheralManager?

    /// Custom Balcony BLE service UUID.
    static let serviceUUID = CBUUID(string: "B41C0000-0001-0001-0001-000000000001")
    static let deviceCharacteristicUUID = CBUUID(string: "B41C0001-0001-0001-0001-000000000001")

    private var deviceName: String = "Mac"
    private var deviceIdentityData: Data?

    override init() {
        super.init()
    }

    /// Start advertising as a BLE peripheral.
    func startAdvertising(deviceName: String) {
        self.deviceName = deviceName

        // Pre-encode the device identity JSON that will be served via the characteristic
        let identity: [String: String] = [
            "name": deviceName,
            "id": Host.current().localizedName ?? UUID().uuidString
        ]
        self.deviceIdentityData = try? JSONSerialization.data(withJSONObject: identity)

        peripheralManager = CBPeripheralManager(delegate: self, queue: .global())
        logger.info("BLE peripheral manager initialized")
    }

    /// Stop advertising.
    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        peripheralManager = nil
        logger.info("BLE peripheral stopped")
    }

    // MARK: - Service Setup

    private func setupService() {
        guard let manager = peripheralManager else { return }

        let deviceCharacteristic = CBMutableCharacteristic(
            type: Self.deviceCharacteristicUUID,
            properties: [.read],
            value: deviceIdentityData,
            permissions: [.readable]
        )

        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [deviceCharacteristic]

        manager.add(service)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("BLE powered on - setting up services")
            setupService()
        case .poweredOff:
            logger.warning("BLE powered off")
        case .unauthorized:
            logger.warning("BLE unauthorized")
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            logger.error("Failed to add BLE service: \(error.localizedDescription)")
            return
        }

        logger.info("BLE service added, starting advertising")
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: deviceName
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            logger.error("Failed to start BLE advertising: \(error.localizedDescription)")
            return
        }
        logger.info("BLE advertising started")
    }
}
