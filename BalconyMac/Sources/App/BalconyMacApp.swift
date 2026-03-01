import SwiftUI
import BalconyShared

@main
struct BalconyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
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
