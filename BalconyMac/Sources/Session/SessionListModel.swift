import Foundation
import BalconyShared

/// @MainActor view model that exposes session data for SwiftUI.
///
/// PTYSessionManager is an actor, so its data can't be directly observed
/// by SwiftUI views. This model bridges the gap.
@MainActor
final class SessionListModel: ObservableObject {
    @Published var sessions: [Session] = []

    /// Sessions most-recently-active first.
    ///
    /// Callers that also care about whether a session is *waiting* on the user
    /// layer that on top — see `MenuBarView.prioritizedSessions`, which ranks by
    /// attention state and falls back to this order within each rank.
    var sessionsByActivity: [Session] {
        sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }
}
