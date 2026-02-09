import SwiftUI
import BalconyShared

struct DeviceManagementView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        List {
            if connectionManager.pairedDevices.isEmpty {
                if #available(iOS 17.0, *) {
                    ContentUnavailableView(
                        "No Paired Devices",
                        systemImage: "desktopcomputer",
                        description: Text("Scan a QR code on your Mac to pair.")
                    )
                } else {
                    Text("No Paired Devices")
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
            } else {
                ForEach(connectionManager.pairedDevices, id: \.id) { device in
                    HStack {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.headline)
                            Text("Fingerprint: \(device.publicKeyFingerprint.prefix(8))...")
                                .font(.caption)
                                .foregroundStyle(BalconyTheme.textSecondary)
                        }
                        Spacer()
                        if connectionManager.connectedDevice?.id == device.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BalconyTheme.statusGreen)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let device = connectionManager.pairedDevices[index]
                        connectionManager.removePairedDevice(device)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BalconyTheme.background)
        .navigationTitle("Devices")
    }
}
