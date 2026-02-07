import SwiftUI

struct SettingsView: View {
    @AppStorage("notify.sessionEvents") private var notifySessionEvents = true
    @AppStorage("notify.toolApprovals") private var notifyToolApprovals = true
    @AppStorage("notify.sessionComplete") private var notifySessionComplete = true
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Connected Macs") {
                    NavigationLink("Manage Devices") {
                        DeviceManagementView()
                    }
                }

                Section("Notifications") {
                    Toggle("Session Events", isOn: $notifySessionEvents)
                    Toggle("Tool Approvals", isOn: $notifyToolApprovals)
                    Toggle("Session Complete", isOn: $notifySessionComplete)
                }

                Section("Security") {
                    Button("Reset Encryption Keys") {
                        showResetConfirmation = true
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
            .alert("Reset Encryption Keys?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    // Clear paired devices and keys — user will need to re-pair
                    UserDefaults.standard.removeObject(forKey: "com.balcony.pairedDevices")
                }
            } message: {
                Text("This will remove all paired devices. You will need to scan the QR code on your Mac again to reconnect.")
            }
        }
    }
}
