import SwiftUI
import BalconyShared

@main
struct BalconyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var updaterService = UpdaterService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                updaterService: updaterService,
                onSelectSession: { appDelegate.revealSession($0) }
            )
            .environmentObject(appDelegate.connectionManager)
            .environmentObject(appDelegate.sessionListModel)
            .environmentObject(appDelegate.hookEventHandler)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}
