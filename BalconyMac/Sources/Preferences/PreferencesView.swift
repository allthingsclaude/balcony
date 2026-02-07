import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("wsPort") private var wsPort = 29170
    @AppStorage("idleThreshold") private var idleThreshold = 120
    @AppStorage("awayThreshold") private var awayThreshold = 300
    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            // General
            Form {
                Section("Server") {
                    TextField("WebSocket Port", value: $wsPort, format: .number)
                }
                Section("Startup") {
                    Toggle("Start at login", isOn: $loginItemEnabled)
                        .onChange(of: loginItemEnabled) { _, newValue in
                            toggleLoginItem(enabled: newValue)
                        }
                }
            }
            .tabItem { Label("General", systemImage: "gear") }
            .frame(width: 400, height: 200)

            // Away Detection
            Form {
                Section("Away Detection") {
                    Stepper("Idle threshold: \(idleThreshold)s", value: $idleThreshold, in: 30...600, step: 30)
                    Stepper("Away threshold: \(awayThreshold)s", value: $awayThreshold, in: 60...1800, step: 60)
                }
            }
            .tabItem { Label("Away Detection", systemImage: "person.wave.2") }
            .frame(width: 400, height: 200)
        }
    }

    private func toggleLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert toggle on failure
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
