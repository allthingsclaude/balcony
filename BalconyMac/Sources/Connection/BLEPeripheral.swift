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

    override init() {
        super.init()
    }

    /// Start advertising as a BLE peripheral.
    func startAdvertising(deviceName: String) {
        peripheralManager = CBPeripheralManager(delegate: self, queue: .global())
        logger.info("BLE peripheral manager initialized")
    }

    /// Stop advertising.
    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
        logger.info("BLE peripheral stopped")
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheral: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            logger.info("BLE powered on - setting up services")
            // TODO: Add Balcony service and characteristics
            // TODO: Start advertising
        case .poweredOff:
            logger.warning("BLE powered off")
        case .unauthorized:
            logger.warning("BLE unauthorized")
        default:
            break
        }
    }
}
