import Foundation
import os

/// Advertises the BalconyMac service via Bonjour for zero-config discovery.
///
/// Uses NetService to register on the same port as the SwiftNIO WebSocket
/// server without needing to bind a second listener.
@MainActor
final class BonjourAdvertiser: NSObject, NetServiceDelegate {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "BonjourAdvertiser")
    private var netService: NetService?
    private let port: UInt16
    private let deviceName: String

    init(port: UInt16 = 29170, deviceName: String = Host.current().localizedName ?? "Mac") {
        self.port = port
        self.deviceName = deviceName
        super.init()
    }

    /// Start advertising the Balcony service.
    func startAdvertising(publicKeyFingerprint: String) {
        let service = NetService(
            domain: "",
            type: "_balcony._tcp.",
            name: deviceName,
            port: Int32(port)
        )
        service.delegate = self

        let txtData = NetService.data(fromTXTRecord: [
            "v": "1".data(using: .utf8)!,
            "name": deviceName.data(using: .utf8)!,
            "pk": publicKeyFingerprint.data(using: .utf8)!,
        ])
        service.setTXTRecord(txtData)
        service.publish()

        self.netService = service
        logger.info("Started Bonjour advertising: _balcony._tcp. on port \(self.port)")
    }

    /// Stop advertising.
    func stopAdvertising() {
        netService?.stop()
        netService = nil
        logger.info("Stopped Bonjour advertising")
    }

    // MARK: - NetServiceDelegate

    nonisolated func netServiceDidPublish(_ sender: NetService) {
        let name = sender.name
        Task { @MainActor in
            logger.info("Bonjour service published: \(name)")
        }
    }

    nonisolated func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Task { @MainActor in
            logger.error("Bonjour service failed to publish: \(errorDict)")
        }
    }
}
