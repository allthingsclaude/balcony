import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Connected Macs") {
                    NavigationLink("Manage Devices") {
                        DeviceManagementView()
                    }
                }

                Section("Notifications") {
                    Toggle("Session Events", isOn: .constant(true))
                    Toggle("Tool Approvals", isOn: .constant(true))
                    Toggle("Session Complete", isOn: .constant(true))
                }

                Section("Security") {
                    Button("Reset Encryption Keys") {
                        // TODO: Reset and re-pair
                    }
                    .foregroundStyle(.red)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
