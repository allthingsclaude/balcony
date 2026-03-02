import Foundation

/// Payload for BLE RSSI reports sent from iOS to Mac.
public struct BLERSSIReportPayload: Codable, Sendable {
    /// RSSI value in dBm.
    public let rssi: Int

    public init(rssi: Int) {
        self.rssi = rssi
    }
}
