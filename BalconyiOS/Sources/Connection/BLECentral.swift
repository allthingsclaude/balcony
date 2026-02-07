import Foundation
import CoreBluetooth
import os

/// BLE Central for proximity detection of Mac.
final class BLECentral: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "BLECentral")
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?

    @Published var rssi: Int?
    @Published var isScanning = false

    /// Balcony BLE service UUID (must match BalconyMac).
    static let serviceUUID = CBUUID(string: "B41C0000-0001-0001-0001-000000000001")

    override init() {
        super.init()
    }

    /// Start scanning for Balcony peripherals.
    func startScanning() {
        centralManager = CBCentralManager(delegate: self, queue: .global())
    }

    /// Stop scanning.
    func stopScanning() {
        centralManager?.stopScan()
        centralManager = nil
        isScanning = false
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            logger.info("BLE powered on - starting scan")
            central.scanForPeripherals(
                withServices: [Self.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isScanning = true
        case .poweredOff:
            logger.warning("BLE powered off")
            isScanning = false
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        DispatchQueue.main.async {
            self.rssi = RSSI.intValue
        }
        logger.debug("Discovered peripheral RSSI: \(RSSI.intValue)")
    }
}
