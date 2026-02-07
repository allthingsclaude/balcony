import Foundation
import CoreGraphics
import BalconyShared
import os

/// Detects user presence using multiple signals.
@MainActor
final class AwayDetector: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "AwayDetector")

    @Published var currentStatus: AwayStatus = .present
    @Published var currentSignals = AwaySignals()

    private var pollTimer: Timer?
    private var screenLocked = false
    private var lockObservers: [NSObjectProtocol] = []

    /// External signal providers. Set these before calling startDetecting.
    var bleRSSIProvider: (() -> Int?)?
    var networkPresenceProvider: (() -> Bool)?

    // MARK: - Lifecycle

    /// Start polling for away signals.
    func startDetecting(interval: TimeInterval = 10.0) {
        registerScreenLockObservers()

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
        removeScreenLockObservers()
        logger.info("Away detection stopped")
    }

    // MARK: - Signal Collection

    private func updateSignals() {
        let idleSeconds = readSystemIdleTime()
        let bleRSSI = bleRSSIProvider?()
        let onLocalNetwork = networkPresenceProvider?() ?? false

        currentSignals = AwaySignals(
            bleRSSI: bleRSSI,
            idleSeconds: idleSeconds,
            screenLocked: screenLocked,
            onLocalNetwork: onLocalNetwork
        )

        let newStatus = currentSignals.computeStatus()
        if newStatus != currentStatus {
            logger.info("Away status changed: \(String(describing: self.currentStatus)) -> \(String(describing: newStatus))")
            currentStatus = newStatus
        }
    }

    // MARK: - System Idle Time

    /// Read seconds since last keyboard/mouse event via CGEventSource.
    private func readSystemIdleTime() -> Int {
        let idleTime = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: ~0)!
        )
        return Int(idleTime)
    }

    // MARK: - Screen Lock Detection

    private func registerScreenLockObservers() {
        let center = DistributedNotificationCenter.default()

        let lockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenLocked = true
            self?.updateSignals()
        }
        lockObservers.append(lockObserver)

        let unlockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenLocked = false
            self?.updateSignals()
        }
        lockObservers.append(unlockObserver)

        logger.info("Screen lock observers registered")
    }

    private func removeScreenLockObservers() {
        let center = DistributedNotificationCenter.default()
        for observer in lockObservers {
            center.removeObserver(observer)
        }
        lockObservers.removeAll()
    }
}
