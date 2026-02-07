import Foundation
import Network
import os

/// Advertises the BalconyMac service via Bonjour for zero-config discovery.
actor BonjourAdvertiser {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "BonjourAdvertiser")
    private var listener: NWListener?
    private let port: UInt16
    private let deviceName: String

    init(port: UInt16 = 29170, deviceName: String = Host.current().localizedName ?? "Mac") {
        self.port = port
        self.deviceName = deviceName
    }

    /// Start advertising the Balcony service.
    func startAdvertising(publicKeyFingerprint: String) throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)

        var txtRecord = NWTXTRecord()
        txtRecord["v"] = "1"
        txtRecord["name"] = deviceName
        txtRecord["pk"] = publicKeyFingerprint

        listener.service = NWListener.Service(
            name: deviceName,
            type: "_balcony._tcp.",
            txtRecord: txtRecord
        )

        listener.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleStateUpdate(state)
            }
        }

        listener.start(queue: .global())
        self.listener = listener
        logger.info("Started Bonjour advertising: _balcony._tcp.")
    }

    /// Stop advertising.
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        logger.info("Stopped Bonjour advertising")
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            logger.info("Bonjour listener ready")
        case .failed(let error):
            logger.error("Bonjour listener failed: \(error.localizedDescription)")
        case .cancelled:
            logger.info("Bonjour listener cancelled")
        default:
            break
        }
    }
}
