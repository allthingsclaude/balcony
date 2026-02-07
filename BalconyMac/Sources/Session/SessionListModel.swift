import Foundation
import BalconyShared

/// @MainActor view model that exposes session data for SwiftUI.
///
/// SessionMonitor is an actor, so its data can't be directly observed
/// by SwiftUI views. This model bridges the gap.
@MainActor
final class SessionListModel: ObservableObject {
    @Published var sessions: [Session] = []

    /// Active sessions only.
    var activeSessions: [Session] {
        sessions.filter { $0.status == .active || $0.status == .waitingForInput }
    }
}
