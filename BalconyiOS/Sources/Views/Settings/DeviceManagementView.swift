import SwiftUI
import BalconyShared

struct DeviceManagementView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        List {
            if connectionManager.pairedDevices.isEmpty {
                ContentUnavailableView(
                    "No Paired Devices",
                    systemImage: "desktopcomputer",
                    description: Text("Scan a QR code on your Mac to pair.")
                )
            } else {
                ForEach(connectionManager.pairedDevices, id: \.id) { device in
                    HStack {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.headline)
                            Text("Fingerprint: \(device.publicKeyFingerprint.prefix(8))...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { _ in
                    // TODO: Unpair device
                }
            }
        }
        .navigationTitle("Devices")
    }
}
