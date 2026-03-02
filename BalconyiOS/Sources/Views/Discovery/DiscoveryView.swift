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
                        if connectionManager.isAutoConnecting {
                            Text("Connecting to \(autoConnectDeviceName)...")
                                .font(BalconyTheme.headingFont(22))
                                .foregroundStyle(BalconyTheme.textPrimary)
                            Text("Reconnecting automatically")
                                .font(BalconyTheme.bodyFont(14))
                                .foregroundStyle(BalconyTheme.textSecondary)
                        } else {
                            Text("Looking for your Mac...")
                                .font(BalconyTheme.headingFont(22))
                                .foregroundStyle(BalconyTheme.textPrimary)
                            Text("Searching on Wi-Fi and Bluetooth")
                                .font(BalconyTheme.bodyFont(14))
                                .foregroundStyle(BalconyTheme.textSecondary)
                        }
                    }

                    // Discovered devices
                    if !connectionManager.discoveredDevices.isEmpty && !connectionManager.isAutoConnecting {
                        VStack(alignment: .leading, spacing: BalconyTheme.spacingSM) {
                            sectionHeader("AVAILABLE")

                            ForEach(connectionManager.discoveredDevices, id: \.id) { device in
                                DeviceCardView(device: device, isConnecting: connectionManager.isConnecting) {
                                    BalconyTheme.hapticMedium()
                                    Task {
                                        await connectionManager.connect(to: device)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, BalconyTheme.spacingLG)
                    }

                    // Previously paired (offline)
                    if !offlinePairedDevices.isEmpty && !connectionManager.isAutoConnecting {
                        VStack(alignment: .leading, spacing: BalconyTheme.spacingSM) {
                            sectionHeader("PREVIOUSLY PAIRED")

                            ForEach(offlinePairedDevices, id: \.id) { device in
                                DeviceCardView(device: device, isConnecting: false, dimmed: true) {}
                            }
                        }
                        .padding(.horizontal, BalconyTheme.spacingLG)
                    }

                    // Cancel auto-connect button
                    if connectionManager.isAutoConnecting {
                        Button {
                            BalconyTheme.hapticLight()
                            connectionManager.cancelAutoConnect()
                        } label: {
                            Text("Cancel")
                                .font(BalconyTheme.bodyFont(15))
                                .fontWeight(.medium)
                                .foregroundStyle(BalconyTheme.textSecondary)
                                .padding(.vertical, 10)
                                .padding(.horizontal, BalconyTheme.spacingXL)
                        }
                        .modifier(LiquidGlassCapsule())
                    }

                    // How It Works (when no devices)
                    if connectionManager.discoveredDevices.isEmpty && !connectionManager.isAutoConnecting {
                        HowItWorksSection()
                            .padding(.horizontal, BalconyTheme.spacingLG)

                        // Tip card
                        TipCardView()
                            .padding(.horizontal, BalconyTheme.spacingLG)
                    }
                }
                .padding(.bottom, 120)
            }

            // Bottom fade + floating QR button (hidden during auto-connect)
            if !connectionManager.isAutoConnecting {
                VStack(spacing: 0) {
                    Spacer()

                    BalconyTheme.bottomFadeGradient()
                        .frame(height: 150)
                        .offset(y: 100)
                        .allowsHitTesting(false)

                    Button {
                        BalconyTheme.hapticLight()
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
        }
        .background(BalconyTheme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.3), value: connectionManager.isAutoConnecting)
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
        .onChange(of: connectionManager.isConnected) { connected in
            if connected { BalconyTheme.hapticSuccess() }
        }
        .onChange(of: connectionManager.connectionError) { error in
            showingError = error != nil
            if error != nil { BalconyTheme.hapticError() }
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

    /// Name of the device being auto-connected to, for display.
    private var autoConnectDeviceName: String {
        if let lastId = connectionManager.lastConnectedDeviceId,
           let device = connectionManager.discoveredDevices.first(where: { $0.id == lastId }) {
            return device.name
        }
        return "your Mac"
    }

    private var offlinePairedDevices: [DeviceInfo] {
        connectionManager.pairedDevices.filter { paired in
            !connectionManager.discoveredDevices.contains { $0.id == paired.id }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        BalconyTheme.sectionHeader(title)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<3, id: \.self) { index in
                    PulseRing(index: index, animate: animate)
                }
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
        .accessibilityLabel("Searching for nearby Macs")
        .onAppear {
            if !reduceMotion { animate = true }
        }
    }
}

/// Individual pulse ring that manages its own repeating animation via TimelineView.
private struct PulseRing: View {
    let index: Int
    let animate: Bool

    private let duration: Double = 2.4
    private let baseSize: CGFloat = 56
    private let maxSize: CGFloat = 120

    var body: some View {
        TimelineView(.animation(paused: !animate)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let staggerDelay = Double(index) * 0.8
            let progress = fract((elapsed - staggerDelay) / duration)
            let eased = 1 - (1 - progress) * (1 - progress) // easeOut quad
            let size = baseSize + (maxSize - baseSize) * eased
            let opacity = 0.25 * (1 - eased)

            Circle()
                .stroke(BalconyTheme.accent.opacity(opacity), lineWidth: 1.5)
                .frame(width: size, height: size)
        }
    }

    private func fract(_ x: Double) -> Double {
        x - x.rounded(.down)
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
        .buttonStyle(ScaleButtonStyle())
        .disabled(isConnecting || dimmed)
        .accessibilityLabel("\(device.name), \(dimmed ? "offline" : "available")")
    }
}

// MARK: - How It Works

private struct HowItWorksSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BalconyTheme.spacingMD) {
            BalconyTheme.sectionHeader("HOW IT WORKS")

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
        .accessibilityElement(children: .combine)
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
