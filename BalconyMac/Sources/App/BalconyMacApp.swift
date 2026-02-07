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
            let iconName = appDelegate.connectionManager.statusIconName
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}
