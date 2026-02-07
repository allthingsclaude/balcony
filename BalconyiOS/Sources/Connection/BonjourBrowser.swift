import Foundation
import Network
import BalconyShared
import os

/// Discovers BalconyMac instances on the local network via Bonjour.
actor BonjourBrowser {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "BonjourBrowser")
    private var browser: NWBrowser?

    /// Discovered devices callback.
    private var onDeviceFound: (@Sendable (DeviceInfo, NWEndpoint) -> Void)?
    private var onDeviceLost: (@Sendable (String) -> Void)?

    /// Set the callback for when a device is discovered.
    func setOnDeviceFound(_ handler: @escaping @Sendable (DeviceInfo, NWEndpoint) -> Void) {
        onDeviceFound = handler
    }

    /// Set the callback for when a device is lost.
    func setOnDeviceLost(_ handler: @escaping @Sendable (String) -> Void) {
        onDeviceLost = handler
    }

    /// Start browsing for Balcony services.
    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_balcony._tcp.", domain: nil), using: params)

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { [weak self] in
                await self?.handleResults(results, changes: changes)
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleState(state)
            }
        }

        browser.start(queue: .global())
        self.browser = browser
        logger.info("Started Bonjour browsing for _balcony._tcp.")
    }

    /// Stop browsing.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        logger.info("Stopped Bonjour browsing")
    }

    // MARK: - Result Handling

    private func handleResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                logger.info("Discovered: \(String(describing: result.endpoint))")
                if let deviceInfo = extractDeviceInfo(from: result) {
                    onDeviceFound?(deviceInfo, result.endpoint)
                }
            case .removed(let result):
                let endpointId = endpointIdentifier(result.endpoint)
                logger.info("Lost: \(endpointId)")
                onDeviceLost?(endpointId)
            default:
                break
            }
        }
    }

    private func handleState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            logger.info("Browser ready")
        case .failed(let error):
            logger.error("Browser failed: \(error.localizedDescription)")
        default:
            break
        }
    }

    // MARK: - TXT Record Parsing

    private func extractDeviceInfo(from result: NWBrowser.Result) -> DeviceInfo? {
        guard case .service(let name, _, _, _) = result.endpoint else {
            return nil
        }

        // Extract TXT record from metadata
        var deviceName = name
        var publicKeyFingerprint = ""

        if case .bonjour(let txtRecord) = result.metadata {
            if let nameValue = txtRecord["name"] {
                deviceName = nameValue
            }
            if let pkValue = txtRecord["pk"] {
                publicKeyFingerprint = pkValue
            }
        }

        return DeviceInfo(
            id: endpointIdentifier(result.endpoint),
            name: deviceName,
            platform: .macOS,
            publicKeyFingerprint: publicKeyFingerprint
        )
    }

    private func endpointIdentifier(_ endpoint: NWEndpoint) -> String {
        if case .service(let name, let type, let domain, _) = endpoint {
            return "\(name).\(type)\(domain)"
        }
        return endpoint.debugDescription
    }
}
