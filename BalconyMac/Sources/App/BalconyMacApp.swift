import SwiftUI
import BalconyShared

@main
struct BalconyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Balcony", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
        }
    }
}
