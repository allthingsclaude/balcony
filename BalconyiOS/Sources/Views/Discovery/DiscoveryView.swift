import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Searching for Macs...")
                .font(.title2)

            if connectionManager.discoveredDevices.isEmpty {
                ProgressView()
                    .padding()
                Text("Make sure BalconyMac is running\non your Mac")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                List(connectionManager.discoveredDevices, id: \.id) { device in
                    Button {
                        Task {
                            await connectionManager.connect(to: device)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "desktopcomputer")
                            Text(device.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            Spacer()

            Button("Scan QR Code") {
                // TODO: Present QR scanner
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Balcony")
        .onAppear {
            connectionManager.startDiscovery()
        }
    }
}
