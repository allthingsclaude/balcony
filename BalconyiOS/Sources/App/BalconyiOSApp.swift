import SwiftUI
import BalconyShared

@main
struct BalconyiOSApp: App {
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionManager)
                .environmentObject(sessionManager)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        NavigationStack {
            if connectionManager.isConnected {
                SessionListView()
            } else {
                DiscoveryView()
            }
        }
    }
}
