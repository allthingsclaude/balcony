import AppKit
import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let rerunSetupWizard = Notification.Name("com.balcony.rerunSetupWizard")
}

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            ConnectionTab()
                .tabItem { Label("Connection", systemImage: "network") }

            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }

            AwayDetectionTab()
                .tabItem { Label("Away Detection", systemImage: "person.wave.2") }

            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @AppStorage(PreferencesManager.displayNameKey) private var displayName = ""
    @AppStorage(PreferencesManager.sessionRefreshIntervalKey) private var sessionRefreshInterval = 10

    private var displayNamePlaceholder: String {
        Host.current().localizedName ?? "Mac"
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start at login", isOn: $loginItemEnabled)
                    .onChange(of: loginItemEnabled) { _, newValue in
                        toggleLoginItem(enabled: newValue)
                    }
            }
            Section("Identity") {
                TextField("Computer name", text: $displayName, prompt: Text(displayNamePlaceholder))
                    .textFieldStyle(.roundedBorder)
            }
            Section("Session Monitoring") {
                Stepper(
                    "Refresh interval: \(sessionRefreshInterval)s",
                    value: $sessionRefreshInterval,
                    in: 5...60,
                    step: 5
                )
            }
        }
        .formStyle(.grouped)
    }

    private func toggleLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Connection Tab

private struct ConnectionTab: View {
    @AppStorage(PreferencesManager.wsPortKey) private var wsPort = 29170
    @AppStorage(PreferencesManager.bonjourEnabledKey) private var bonjourEnabled = true
    @AppStorage(PreferencesManager.bleEnabledKey) private var bleEnabled = true

    var body: some View {
        Form {
            Section("WebSocket Server") {
                TextField("Port", value: $wsPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            Section("Discovery") {
                Toggle("Enable Bonjour discovery", isOn: $bonjourEnabled)
                Toggle("Enable Bluetooth LE", isOn: $bleEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications Tab

private struct NotificationsTab: View {
    @AppStorage(PreferencesManager.showAttentionPanelKey) private var showAttentionPanel = true
    @AppStorage(PreferencesManager.showDonePanelKey) private var showDonePanel = true
    @AppStorage(PreferencesManager.voiceInputEnabledKey) private var voiceInputEnabled = false
    @AppStorage(PreferencesManager.attentionSoundKey) private var attentionSound = ""
    @AppStorage(PreferencesManager.doneSoundKey) private var doneSound = ""

    var body: some View {
        Form {
            Section("Voice Input") {
                Toggle("Enable voice input", isOn: $voiceInputEnabled)
                Text("Double-tap ⌘ and hold to dictate a response. Release to send.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Attention") {
                Toggle("Show panel", isOn: $showAttentionPanel)
                Picker("Sound", selection: $attentionSound) {
                    Text("None").tag("")
                    Divider()
                    ForEach(PreferencesManager.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: attentionSound) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    NSSound(named: NSSound.Name(newValue))?.play()
                }
                Text("When Claude needs your approval or answer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Done") {
                Toggle("Show panel", isOn: $showDonePanel)
                Picker("Sound", selection: $doneSound) {
                    Text("None").tag("")
                    Divider()
                    ForEach(PreferencesManager.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: doneSound) { _, newValue in
                    guard !newValue.isEmpty else { return }
                    NSSound(named: NSSound.Name(newValue))?.play()
                }
                Text("When Claude finishes and is ready for your next prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Away Detection Tab

private struct AwayDetectionTab: View {
    @AppStorage(PreferencesManager.idleThresholdKey) private var idleThreshold = 120
    @AppStorage(PreferencesManager.awayThresholdKey) private var awayThreshold = 300
    @AppStorage(PreferencesManager.awayDistanceKey) private var awayDistance = 1
    @AppStorage(PreferencesManager.awaySustainKey) private var awaySustain = 3

    private static let distanceOptions = [1, 2, 3, 5, 10]
    private static let sustainOptions = [2, 3, 5, 10, 30]

    var body: some View {
        Form {
            Section("Proximity") {
                Picker("Away distance", selection: $awayDistance) {
                    ForEach(Self.distanceOptions, id: \.self) { meters in
                        Text("~\(meters) meter\(meters == 1 ? "" : "s")").tag(meters)
                    }
                }
                Picker("Sustain time", selection: $awaySustain) {
                    ForEach(Self.sustainOptions, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                Text("Signal must hold for this long before status changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Inactivity Thresholds") {
                Stepper("Idle threshold: \(idleThreshold)s", value: $idleThreshold, in: 30...600, step: 30)
                Stepper("Away threshold: \(awayThreshold)s", value: $awayThreshold, in: 60...1800, step: 60)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced Tab

private struct AdvancedTab: View {
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Setup") {
                Button("Re-run Setup Wizard...") {
                    rerunSetup()
                }
            }
            Section("Danger Zone") {
                Button("Reset All Settings", role: .destructive) {
                    showResetConfirmation = true
                }
                .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        PreferencesManager.shared.resetAll()
                    }
                } message: {
                    Text("This will restore all preferences to their default values.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func rerunSetup() {
        NotificationCenter.default.post(name: .rerunSetupWizard, object: nil)
    }
}
