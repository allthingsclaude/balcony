import SwiftUI

struct MenuBarView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text("Balcony")
                    .font(.headline)
                Spacer()
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Connected Devices
            Section("Devices") {
                Text("No devices connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Active Sessions
            Section("Sessions") {
                Text("No active sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Actions
            Button("Pair New Device...") {
                // TODO: Show QR code pairing view
            }

            Button("Preferences...") {
                // TODO: Open preferences window
            }

            Divider()

            Button("Quit Balcony") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
    }
}
