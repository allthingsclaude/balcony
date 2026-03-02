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
    private var defaultsObserver: NSObjectProtocol?

    /// Hysteresis: the candidate status must be sustained for enough consecutive
    /// poll cycles (derived from sustain time / poll interval) before the published
    /// status actually changes.
    static let pollInterval: TimeInterval = 2.0
    private var candidateStatus: AwayStatus?
    private var candidatePollCount = 0

    /// External signal providers. Set these before calling startDetecting.
    var bleRSSIProvider: (() -> Int?)?
    var networkPresenceProvider: (() -> Bool)?

    // MARK: - Lifecycle

    /// Start polling for away signals.
    func startDetecting() {
        registerScreenLockObservers()

        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSignals()
            }
        }
        logger.info("Away detection started (poll: \(Self.pollInterval)s)")
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

        let prefs = PreferencesManager.shared
        let rssiThreshold = PreferencesManager.rssiThreshold(forMeters: prefs.awayDistance)
        let rawStatus = currentSignals.computeStatus(
            idleThreshold: prefs.idleThreshold,
            awayThreshold: prefs.awayThreshold,
            rssiThreshold: rssiThreshold
        )

        // Screen lock/unlock transitions immediately (no hysteresis needed)
        if rawStatus == .locked || currentStatus == .locked {
            commitStatus(rawStatus)
            return
        }

        // For all other transitions, require sustained signal to avoid flapping
        let requiredPolls = max(1, Int(Double(prefs.awaySustain) / Self.pollInterval))
        if rawStatus != currentStatus {
            if rawStatus == candidateStatus {
                candidatePollCount += 1
            } else {
                candidateStatus = rawStatus
                candidatePollCount = 1
            }

            if candidatePollCount >= requiredPolls {
                commitStatus(rawStatus)
            }
        } else {
            // Signal matches current status — reset any pending transition
            candidateStatus = nil
            candidatePollCount = 0
        }
    }

    private func commitStatus(_ newStatus: AwayStatus) {
        if newStatus != currentStatus {
            logger.info("Away status changed: \(String(describing: self.currentStatus)) -> \(String(describing: newStatus))")
            currentStatus = newStatus
        }
        candidateStatus = nil
        candidatePollCount = 0
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
