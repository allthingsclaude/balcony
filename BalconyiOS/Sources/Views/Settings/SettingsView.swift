import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("appIcon") private var appIcon: String = "light"
    @AppStorage("notify.toolApprovals") private var notifyToolApprovals = true
    @AppStorage("notify.sessionComplete") private var notifySessionComplete = true
    @AppStorage(SoundManager.attentionSoundKey) private var attentionSound: String = NotificationSound.signal.rawValue
    @AppStorage(SoundManager.doneSoundKey) private var doneSound: String = NotificationSound.breeze.rawValue
    @AppStorage("input.autocorrect") private var autocorrectEnabled = false
    @State private var showResetConfirmation = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Connected Macs") {
                    NavigationLink("Manage Devices") {
                        DeviceManagementView()
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Picker("App Icon", selection: $appIcon) {
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section("Notifications") {
                    Toggle("Tool Approvals", isOn: $notifyToolApprovals)
                    Toggle("Session Complete", isOn: $notifySessionComplete)
                    Text("Delivered when the notifications switch in the sidebar is on (it arms automatically when you walk away from your Mac).")
                        .font(.caption)
                        .foregroundStyle(BalconyTheme.textSecondary)
                }

                Section("Notification Sounds") {
                    Picker("Attention Sound", selection: $attentionSound) {
                        ForEach(NotificationSound.allCases) { sound in
                            Text(sound.displayName).tag(sound.rawValue)
                        }
                    }
                    .onChange(of: attentionSound) { newValue in
                        if let sound = NotificationSound(rawValue: newValue) {
                            SoundManager.shared.play(sound)
                        }
                    }
                    Text("Played when Claude needs your approval or answer.")
                        .font(.caption)
                        .foregroundStyle(BalconyTheme.textSecondary)

                    Picker("Done Sound", selection: $doneSound) {
                        ForEach(NotificationSound.allCases) { sound in
                            Text(sound.displayName).tag(sound.rawValue)
                        }
                    }
                    .onChange(of: doneSound) { newValue in
                        if let sound = NotificationSound(rawValue: newValue) {
                            SoundManager.shared.play(sound)
                        }
                    }
                    Text("Played when Claude finishes and is ready for input.")
                        .font(.caption)
                        .foregroundStyle(BalconyTheme.textSecondary)
                }

                Section("Input") {
                    Toggle("Autocorrect", isOn: $autocorrectEnabled)
                    Text("When off, autocapitalization is also disabled — safer for commands and file paths.")
                        .font(.caption)
                        .foregroundStyle(BalconyTheme.textSecondary)
                }

                Section("Security") {
                    Button("Reset Encryption Keys") {
                        showResetConfirmation = true
                    }
                    .foregroundStyle(BalconyTheme.statusRed)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(BalconyTheme.textSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BalconyTheme.background)
            .navigationTitle("Settings")
            .alert("Reset Encryption Keys?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    // Clear paired devices, auto-reconnect, and keys — user will need to re-pair
                    UserDefaults.standard.removeObject(forKey: "com.balcony.pairedDevices")
                    UserDefaults.standard.removeObject(forKey: "com.balcony.lastConnectedDeviceId")
                }
            } message: {
                Text("This will remove all paired devices. You will need to scan the QR code on your Mac again to reconnect.")
            }
        }
    }
}
