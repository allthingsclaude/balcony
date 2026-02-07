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
    public func computeStatus() -> AwayStatus {
        if screenLocked {
            return .locked
        } else if bleRSSI == nil && !onLocalNetwork {
            return .away
        } else if idleSeconds > 300 || (bleRSSI != nil && bleRSSI! < -80) {
            return .idle
        } else if idleSeconds > 120 {
            return .idle
        } else {
            return .present
        }
    }
}
