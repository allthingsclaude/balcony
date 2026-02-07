import Foundation
import BalconyShared
import os

/// Detects user presence using multiple signals.
@MainActor
final class AwayDetector: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AwayDetector")

    @Published var currentStatus: AwayStatus = .present
    @Published var currentSignals = AwaySignals()

    private var pollTimer: Timer?

    /// Start polling for away signals.
    func startDetecting(interval: TimeInterval = 10.0) {
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSignals()
            }
        }
        logger.info("Away detection started (interval: \(interval)s)")
    }

    /// Stop polling.
    func stopDetecting() {
        pollTimer?.invalidate()
        pollTimer = nil
        logger.info("Away detection stopped")
    }

    private func updateSignals() {
        // TODO: Read system idle time from CGEventSource
        // TODO: Check screen lock state via DistributedNotificationCenter
        // TODO: Get BLE RSSI from connected iOS device
        // TODO: Check if iOS device is on local network

        // Placeholder values
        currentSignals = AwaySignals(
            bleRSSI: nil,
            idleSeconds: 0,
            screenLocked: false,
            onLocalNetwork: true
        )

        let newStatus = currentSignals.computeStatus()
        if newStatus != currentStatus {
            logger.info("Away status changed: \(String(describing: self.currentStatus)) -> \(String(describing: newStatus))")
            currentStatus = newStatus
        }
    }
}
