import Foundation

/// User presence state determined by multi-signal away detection.
public enum AwayStatus: String, Codable, Sendable {
    /// User is actively at the Mac.
    case present
    /// User appears idle (no recent input but still nearby).
    case idle
    /// User has left (no BLE signal, no network presence).
    case away
    /// Mac screen is locked.
    case locked
}

/// Raw signals used to determine away status.
public struct AwaySignals: Codable, Sendable {
    /// BLE RSSI in dBm. nil if device not found.
    public var bleRSSI: Int?
    /// Seconds since last keyboard/mouse event.
    public var idleSeconds: Int
    /// Whether the Mac screen is locked.
    public var screenLocked: Bool
    /// Whether the iPhone is visible on the local network.
    public var onLocalNetwork: Bool

    public init(
        bleRSSI: Int? = nil,
        idleSeconds: Int = 0,
        screenLocked: Bool = false,
        onLocalNetwork: Bool = true
    ) {
        self.bleRSSI = bleRSSI
        self.idleSeconds = idleSeconds
        self.screenLocked = screenLocked
        self.onLocalNetwork = onLocalNetwork
    }

    /// Compute the away status from current signals.
    ///
    /// - Parameters:
    ///   - idleThreshold: Seconds of inactivity before marking idle (default 120).
    ///   - awayThreshold: Seconds of inactivity contributing to idle when signal is weak (default 300).
    ///   - rssiThreshold: BLE RSSI in dBm below which the device is considered far away (default -80).
    public func computeStatus(
        idleThreshold: Int = 120,
        awayThreshold: Int = 300,
        rssiThreshold: Int = -80
    ) -> AwayStatus {
        if screenLocked {
            return .locked
        } else if bleRSSI == nil && !onLocalNetwork {
            return .away
        } else if idleSeconds > awayThreshold || (bleRSSI != nil && bleRSSI! < rssiThreshold) {
            return .idle
        } else if idleSeconds > idleThreshold {
            return .idle
        } else {
            return .present
        }
    }
}
