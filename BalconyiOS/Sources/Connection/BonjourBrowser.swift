import Foundation
import Network
import BalconyShared
import os

/// Discovers BalconyMac instances on the local network via Bonjour.
actor BonjourBrowser {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "BonjourBrowser")
    private var browser: NWBrowser?

    /// Discovered devices callback.
    var onDeviceFound: ((DeviceInfo) -> Void)?
    var onDeviceLost: ((String) -> Void)?

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

    private func handleResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                logger.info("Discovered: \(String(describing: result.endpoint))")
                // TODO: Extract device info from endpoint and TXT record
            case .removed(let result):
                logger.info("Lost: \(String(describing: result.endpoint))")
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
}
