import SwiftUI
import BalconyShared

struct DiscoveryView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingQRScanner = false

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
                showingQRScanner = true
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Balcony")
        .onAppear {
            connectionManager.startDiscovery()
        }
        .sheet(isPresented: $showingQRScanner) {
            QRScannerView { scannedURL in
                handleScannedURL(scannedURL)
            }
        }
    }

    private func handleScannedURL(_ urlString: String) {
        guard let components = URLComponents(string: urlString),
              components.scheme == "balcony",
              components.host == "pair",
              let queryItems = components.queryItems,
              let host = queryItems.first(where: { $0.name == "host" })?.value,
              let portString = queryItems.first(where: { $0.name == "port" })?.value,
              let port = Int(portString) else {
            return
        }

        let publicKey = queryItems.first(where: { $0.name == "pk" })?.value

        Task {
            await connectionManager.connectDirect(host: host, port: port, publicKeyBase64: publicKey)
        }
    }
}
