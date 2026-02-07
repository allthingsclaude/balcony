import AppKit
import os

/// Manages the menu bar status item icon and state.
@MainActor
final class StatusItemManager: ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "StatusItem")

    enum ConnectionState {
        case disconnected
        case connected
        case active
    }

    @Published var connectionState: ConnectionState = .disconnected

    var statusIconName: String {
        switch connectionState {
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .connected: return "antenna.radiowaves.left.and.right"
        case .active: return "antenna.radiowaves.left.and.right.circle.fill"
        }
    }
}
