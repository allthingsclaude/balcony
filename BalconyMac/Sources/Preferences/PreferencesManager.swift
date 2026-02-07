import Foundation
import os

/// Manages persistent preferences for BalconyMac.
///
/// Currently preferences are managed via @AppStorage in PreferencesView.
/// This manager is available for programmatic access when needed.
@MainActor
final class PreferencesManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "Preferences")

    static let shared = PreferencesManager()

    var wsPort: Int {
        let port = UserDefaults.standard.integer(forKey: "wsPort")
        return port != 0 ? port : 29170
    }

    var idleThreshold: Int {
        let threshold = UserDefaults.standard.integer(forKey: "idleThreshold")
        return threshold != 0 ? threshold : 120
    }

    var awayThreshold: Int {
        let threshold = UserDefaults.standard.integer(forKey: "awayThreshold")
        return threshold != 0 ? threshold : 300
    }

    private init() {}
}
