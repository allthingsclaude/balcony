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
    static let notifyOnConnectKey = "notifyOnConnect"
    static let notifyOnDisconnectKey = "notifyOnDisconnect"
    static let soundEffectKey = "soundEffect"

    // MARK: - Defaults

    static let defaults: [String: Any] = [
        wsPortKey: 29170,
        idleThresholdKey: 120,
        awayThresholdKey: 300,
        sessionRefreshIntervalKey: 10,
        bonjourEnabledKey: true,
        bleEnabledKey: true,
        notifyOnConnectKey: true,
        notifyOnDisconnectKey: true,
        soundEffectKey: "",
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

    // MARK: - Notifications

    var notifyOnConnect: Bool {
        if UserDefaults.standard.object(forKey: Self.notifyOnConnectKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.notifyOnConnectKey)
    }

    var notifyOnDisconnect: Bool {
        if UserDefaults.standard.object(forKey: Self.notifyOnDisconnectKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: Self.notifyOnDisconnectKey)
    }

    /// Name of the system sound to play on connection events. Empty string means no sound.
    var soundEffect: String {
        return UserDefaults.standard.string(forKey: Self.soundEffectKey) ?? ""
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
    }

    /// Register default values so @AppStorage picks them up.
    private func registerDefaults() {
        UserDefaults.standard.register(defaults: Self.defaults)
    }

    // MARK: - Reset

    /// Remove all Balcony preference keys and re-register defaults.
    func resetAll() {
        let allKeys = [
            Self.wsPortKey, Self.idleThresholdKey, Self.awayThresholdKey,
            Self.displayNameKey, Self.sessionRefreshIntervalKey,
            Self.bonjourEnabledKey, Self.bleEnabledKey,
            Self.notifyOnConnectKey, Self.notifyOnDisconnectKey, Self.soundEffectKey,
        ]
        for key in allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        registerDefaults()
        logger.info("All preferences reset to defaults")
    }
}
