import Foundation
import os

/// Manages persistent preferences for BalconyMac.
final class PreferencesManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "Preferences")

    static let shared = PreferencesManager()

    @Published var wsPort: Int {
        didSet { UserDefaults.standard.set(wsPort, forKey: "wsPort") }
    }

    @Published var autoStart: Bool {
        didSet { UserDefaults.standard.set(autoStart, forKey: "autoStart") }
    }

    private init() {
        let port = UserDefaults.standard.integer(forKey: "wsPort")
        self.wsPort = port != 0 ? port : 29170
        self.autoStart = UserDefaults.standard.bool(forKey: "autoStart")
    }
}
