import SwiftUI
import BalconyShared

@main
struct BalconyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterService = UpdaterService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(updaterService: updaterService)
                .environmentObject(appDelegate.connectionManager)
                .environmentObject(appDelegate.sessionListModel)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}
