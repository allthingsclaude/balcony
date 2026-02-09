import SwiftUI
import BalconyShared

struct DiscoveryView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showingQRScanner = false
    @State private var showingError = false
    @State private var showConnectingBadge = false
    @State private var connectingDelayTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: BalconyTheme.spacingXL) {
                    // Animated search pulse
                    SearchPulseView()
                        .padding(.top, 40)

                    // Header text
                    VStack(spacing: BalconyTheme.spacingSM) {
                        Text("Looking for your Mac...")
                            .font(BalconyTheme.headingFont(22))
                            .foregroundStyle(BalconyTheme.textPrimary)
                        Text("Searching on Wi-Fi and Bluetooth")
                            .font(BalconyTheme.bodyFont(14))
                            .foregroundStyle(BalconyTheme.textSecondary)
                    }

                    // Discovered devices
                    if !connectionManager.discoveredDevices.isEmpty {
                        VStack(alignment: .leading, spacing: BalconyTheme.spacingSM) {
                            sectionHeader("AVAILABLE")

                            ForEach(connectionManager.discoveredDevices, id: \.id) { device in
                                DeviceCardView(device: device, isConnecting: connectionManager.isConnecting) {
                                    Task {
                                        await connectionManager.connect(to: device)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, BalconyTheme.spacingLG)
                    }

                    // Previously paired (offline)
                    if !offlinePairedDevices.isEmpty {
                        VStack(alignment: .leading, spacing: BalconyTheme.spacingSM) {
                            sectionHeader("PREVIOUSLY PAIRED")

                            ForEach(offlinePairedDevices, id: \.id) { device in
                                DeviceCardView(device: device, isConnecting: false, dimmed: true) {}
                            }
                        }
                        .padding(.horizontal, BalconyTheme.spacingLG)
                    }

                    // How It Works (when no devices)
                    if connectionManager.discoveredDevices.isEmpty {
                        HowItWorksSection()
                            .padding(.horizontal, BalconyTheme.spacingLG)

                        // Tip card
                        TipCardView()
                            .padding(.horizontal, BalconyTheme.spacingLG)
                    }
                }
                .padding(.bottom, 120)
            }

            // Bottom fade + floating QR button
            VStack(spacing: 0) {
                Spacer()

                BalconyTheme.bottomFadeGradient()
                    .frame(height: 150)
                    .offset(y: 100)
                    .allowsHitTesting(false)

                Button {
                    showingQRScanner = true
                } label: {
                    HStack(spacing: BalconyTheme.spacingSM) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 16, weight: .medium))
                        Text("Scan QR Code")
                            .font(BalconyTheme.bodyFont(15))
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(BalconyTheme.textPrimary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, BalconyTheme.spacingXL)
                }
                .modifier(LiquidGlassCapsule())
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .disabled(connectionManager.isConnecting)
                .padding(.bottom, BalconyTheme.spacingSM)
            }
        }
        .background(BalconyTheme.background)
        .navigationTitle("")
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
                .padding(.bottom, 70)
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

    // MARK: - Helpers

    private var offlinePairedDevices: [DeviceInfo] {
        connectionManager.pairedDevices.filter { paired in
            !connectionManager.discoveredDevices.contains { $0.id == paired.id }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(BalconyTheme.textSecondary)
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

// MARK: - Search Pulse Animation

private struct SearchPulseView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(BalconyTheme.accent.opacity(animate ? 0 : 0.25), lineWidth: 1.5)
                    .frame(
                        width: animate ? 120 : 56,
                        height: animate ? 120 : 56
                    )
                    .animation(
                        .easeOut(duration: 2.4)
                        .repeatForever(autoreverses: false)
                        .delay(Double(index) * 0.8),
                        value: animate
                    )
            }

            ZStack {
                Circle()
                    .fill(BalconyTheme.surfaceSecondary)
                    .frame(width: 56, height: 56)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundStyle(BalconyTheme.accent)
            }
        }
        .frame(height: 120)
        .onAppear { animate = true }
    }
}

// MARK: - Device Card

private struct DeviceCardView: View {
    let device: DeviceInfo
    let isConnecting: Bool
    var dimmed: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BalconyTheme.spacingMD) {
                ZStack {
                    Circle()
                        .fill(BalconyTheme.accent.opacity(dimmed ? 0.08 : 0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 18))
                        .foregroundStyle(dimmed ? BalconyTheme.textSecondary : BalconyTheme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(BalconyTheme.headingFont(15))
                        .foregroundStyle(BalconyTheme.textPrimary)
                        .opacity(dimmed ? 0.5 : 1)
                    Text(dimmed ? "Offline" : "macOS \u{00B7} Wi-Fi")
                        .font(.caption2)
                        .foregroundStyle(BalconyTheme.textSecondary)
                        .opacity(dimmed ? 0.4 : 0.7)
                }

                Spacer()

                if !dimmed {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(BalconyTheme.accent)
                }
            }
            .padding(BalconyTheme.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                    .fill(BalconyTheme.surfaceSecondary)
            )
        }
        .buttonStyle(.plain)
        .disabled(isConnecting || dimmed)
    }
}

// MARK: - How It Works

private struct HowItWorksSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BalconyTheme.spacingMD) {
            Text("HOW IT WORKS")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(BalconyTheme.textSecondary)

            InstructionStepCard(
                number: 1,
                title: "Launch BalconyMac",
                description: "Open the menu bar app on your Mac"
            )
            InstructionStepCard(
                number: 2,
                title: "Same network",
                description: "Keep your iPhone and Mac on same Wi-Fi"
            )
            InstructionStepCard(
                number: 3,
                title: "Connect",
                description: "Tap a Mac or scan its QR code"
            )
        }
    }
}

private struct InstructionStepCard: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: BalconyTheme.spacingMD) {
            ZStack {
                Circle()
                    .fill(BalconyTheme.accentSubtle)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(BalconyTheme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BalconyTheme.headingFont(14))
                    .foregroundStyle(BalconyTheme.textPrimary)
                Text(description)
                    .font(BalconyTheme.bodyFont(13))
                    .foregroundStyle(BalconyTheme.textSecondary)
            }

            Spacer()
        }
        .padding(BalconyTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: BalconyTheme.radiusMD)
                .fill(BalconyTheme.surfaceSecondary)
        )
    }
}

// MARK: - Tip Card

private struct TipCardView: View {
    var body: some View {
        HStack(spacing: BalconyTheme.spacingSM) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(BalconyTheme.accent)
            Text("Both devices must be on the same Wi-Fi network for discovery to work.")
                .font(BalconyTheme.bodyFont(13))
                .foregroundStyle(BalconyTheme.textSecondary)
        }
        .padding(BalconyTheme.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: BalconyTheme.radiusSM)
                .fill(BalconyTheme.accentSubtle)
        )
    }
}
