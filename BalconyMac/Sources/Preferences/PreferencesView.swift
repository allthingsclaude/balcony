import SwiftUI

struct PreferencesView: View {
    @AppStorage("wsPort") private var wsPort = 29170
    @AppStorage("autoStart") private var autoStart = true
    @AppStorage("idleThreshold") private var idleThreshold = 120
    @AppStorage("awayThreshold") private var awayThreshold = 300

    var body: some View {
        TabView {
            // General
            Form {
                Section("Server") {
                    TextField("WebSocket Port", value: $wsPort, format: .number)
                    Toggle("Start at login", isOn: $autoStart)
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
}
