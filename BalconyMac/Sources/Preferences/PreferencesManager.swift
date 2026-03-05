import Foundation
import os

/// Manages persistent preferences for BalconyMac.
///
/// Preferences are stored in UserDefaults and surfaced via @AppStorage in PreferencesView.
/// This manager provides programmatic access for the rest of the app.
@MainActor
final class PreferencesManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "Preferences")

    static let shared = PreferencesManager()

    // MARK: - Keys

    static let wsPortKey = "wsPort"
    static let idleThresholdKey = "idleThreshold"
    static let awayThresholdKey = "awayThreshold"
    static let displayNameKey = "displayName"
    static let sessionRefreshIntervalKey = "sessionRefreshInterval"
    static let bonjourEnabledKey = "bonjourEnabled"
    static let bleEnabledKey = "bleEnabled"
    static let showAttentionPanelKey = "showAttentionPanel"
    static let showDonePanelKey = "showDonePanel"
    static let attentionSoundKey = "attentionSound"
    static let doneSoundKey = "doneSound"
    static let awayDistanceKey = "awayDistance"
    static let awaySustainKey = "awaySustain"

    // MARK: - Defaults

    static let defaults: [String: Any] = [
        wsPortKey: 29170,
        idleThresholdKey: 120,
        awayThresholdKey: 300,
        sessionRefreshIntervalKey: 10,
        bonjourEnabledKey: true,
        bleEnabledKey: true,
        showAttentionPanelKey: true,
        showDonePanelKey: true,
        attentionSoundKey: "",
        doneSoundKey: "",
        awayDistanceKey: 1,
        awaySustainKey: 3,
    ]

    // MARK: - General

    var wsPort: Int {
        let port = UserDefaults.standard.integer(forKey: Self.wsPortKey)
        return port != 0 ? port : 29170
    }

    var displayName: String {
        let name = UserDefaults.standard.string(forKey: Self.displayNameKey)
        return (name?.isEmpty == false) ? name! : (Host.current().localizedName ?? "Mac")
    }

    var sessionRefreshInterval: Int {
        let interval = UserDefaults.standard.integer(forKey: Self.sessionRefreshIntervalKey)
        return interval != 0 ? interval : 10
    }

    // MARK: - Connection

    var bonjourEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.bonjourEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.bonjourEnabledKey)
    }

    var bleEnabled: Bool {
        if UserDefaults.standard.object(forKey: Self.bleEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.bleEnabledKey)
    }

    // MARK: - Away Detection

    var idleThreshold: Int {
        let threshold = UserDefaults.standard.integer(forKey: Self.idleThresholdKey)
        return threshold != 0 ? threshold : 120
    }

    var awayThreshold: Int {
        let threshold = UserDefaults.standard.integer(forKey: Self.awayThresholdKey)
        return threshold != 0 ? threshold : 300
    }

    /// Distance in meters beyond which the phone is considered "away" (default 1).
    var awayDistance: Int {
        let distance = UserDefaults.standard.integer(forKey: Self.awayDistanceKey)
        return distance != 0 ? distance : 1
    }

    /// Seconds the signal must sustain before an away/present transition commits (default 3).
    var awaySustain: Int {
        let sustain = UserDefaults.standard.integer(forKey: Self.awaySustainKey)
        return sustain != 0 ? sustain : 3
    }

    /// Poll interval scaled to sustain time. Fast (1s) for short sustains, slower for longer ones.
    static func pollInterval(forSustain sustain: Int) -> TimeInterval {
        switch sustain {
        case ...5: return 1.0
        case ...10: return 2.0
        default: return 5.0
        }
    }

    /// Convert a distance in meters to an approximate BLE RSSI threshold in dBm.
    ///
    /// Uses the log-distance path loss model:
    ///   RSSI = measuredPower - 10 * n * log10(distance)
    /// where measuredPower = -59 dBm (typical BLE at 1m) and n = 2.5 (indoor).
    static func rssiThreshold(forMeters meters: Int) -> Int {
        guard meters > 0 else { return -40 }
        let rssi = -59.0 - 25.0 * log10(Double(meters))
        return Int(rssi)
    }

    // MARK: - Notifications

    /// Whether to show the floating panel when AI needs user action.
    var showAttentionPanel: Bool {
        if UserDefaults.standard.object(forKey: Self.showAttentionPanelKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.showAttentionPanelKey)
    }

    /// Whether to show the floating panel when AI finishes.
    var showDonePanel: Bool {
        if UserDefaults.standard.object(forKey: Self.showDonePanelKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.showDonePanelKey)
    }

    /// Name of the system sound to play when AI needs user action. Empty string means no sound.
    var attentionSound: String {
        return UserDefaults.standard.string(forKey: Self.attentionSoundKey) ?? ""
    }

    /// Name of the system sound to play when AI finishes. Empty string means no sound.
    var doneSound: String {
        return UserDefaults.standard.string(forKey: Self.doneSoundKey) ?? ""
    }

    /// Available system sound names.
    static let availableSounds: [String] = {
        let soundsDir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: soundsDir) else { return [] }
        return files
            .filter { $0.hasSuffix(".aiff") }
            .map { $0.replacingOccurrences(of: ".aiff", with: "") }
            .sorted()
    }()

    // MARK: - Init

    private init() {
        registerDefaults()
        migrateOldSoundPreference()
    }

    /// Register default values so @AppStorage picks them up.
    private func registerDefaults() {
        UserDefaults.standard.register(defaults: Self.defaults)
    }

    /// Migrate old single `soundEffect` key to the new dual-sound keys.
    private func migrateOldSoundPreference() {
        let ud = UserDefaults.standard
        if let oldSound = ud.string(forKey: "soundEffect"),
           ud.object(forKey: Self.attentionSoundKey) == nil,
           ud.object(forKey: Self.doneSoundKey) == nil {
            ud.set(oldSound, forKey: Self.attentionSoundKey)
            ud.set(oldSound, forKey: Self.doneSoundKey)
            ud.removeObject(forKey: "soundEffect")
            logger.info("Migrated old soundEffect preference to attention/done sounds")
        }
    }

    // MARK: - Reset

    /// Remove all Balcony preference keys and re-register defaults.
    func resetAll() {
        let allKeys = [
            Self.wsPortKey, Self.idleThresholdKey, Self.awayThresholdKey,
            Self.displayNameKey, Self.sessionRefreshIntervalKey,
            Self.bonjourEnabledKey, Self.bleEnabledKey,
            Self.showAttentionPanelKey, Self.showDonePanelKey,
            Self.attentionSoundKey, Self.doneSoundKey,
            Self.awayDistanceKey, Self.awaySustainKey,
        ]
        for key in allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        registerDefaults()
        logger.info("All preferences reset to defaults")
    }
}
