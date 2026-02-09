import SwiftUI
import BalconyShared

struct DiscoveryView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingQRScanner = false
    @State private var showingError = false
    @State private var showConnectingBadge = false
    @State private var connectingDelayTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(BalconyTheme.accent)

            Text("Searching for Macs...")
                .font(BalconyTheme.headingFont(22))
                .foregroundStyle(BalconyTheme.textPrimary)

            if connectionManager.discoveredDevices.isEmpty {
                ProgressView()
                    .padding()
                Text("Make sure BalconyMac is running\non your Mac")
                    .multilineTextAlignment(.center)
                    .font(BalconyTheme.bodyFont())
                    .foregroundStyle(BalconyTheme.textSecondary)
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
                                .foregroundStyle(BalconyTheme.textSecondary)
                        }
                    }
                    .disabled(connectionManager.isConnecting)
                }
                .listStyle(.insetGrouped)
            }

            Spacer()

            Button {
                showingQRScanner = true
            } label: {
                Text("Scan QR Code")
                    .font(BalconyTheme.bodyFont())
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, BalconyTheme.spacingXL)
                    .padding(.vertical, BalconyTheme.spacingMD)
                    .background(BalconyTheme.accent, in: Capsule())
            }
            .disabled(connectionManager.isConnecting)
        }
        .background(BalconyTheme.background)
        .navigationTitle("Balcony")
        .overlay(alignment: .bottom) {
            if showConnectingBadge {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(BalconyTheme.accent)
                    Text("Connecting...")
                        .font(BalconyTheme.bodyFont(14))
                        .fontWeight(.medium)
                        .foregroundStyle(BalconyTheme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(BalconyTheme.accentSubtle, in: Capsule())
                .overlay(Capsule().stroke(BalconyTheme.accent.opacity(0.3), lineWidth: 1))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showConnectingBadge)
        .onAppear {
            connectionManager.startDiscovery()
        }
        .onChange(of: connectionManager.isConnecting) { connecting in
            connectingDelayTask?.cancel()
            if connecting {
                connectingDelayTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    showConnectingBadge = true
                }
            } else {
                showConnectingBadge = false
            }
        }
        .onChange(of: connectionManager.connectionError) { error in
            showingError = error != nil
        }
        .alert("Connection Failed", isPresented: $showingError) {
            Button("OK") {
                connectionManager.connectionError = nil
            }
        } message: {
            if let error = connectionManager.connectionError {
                Text(error)
            }
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
