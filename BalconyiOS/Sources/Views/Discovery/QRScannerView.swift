import SwiftUI
import AVFoundation

/// Camera-based QR code scanner for device pairing.
struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onScanned: (String) -> Void

    @State private var cameraPermission: AVAuthorizationStatus = .notDetermined
    @State private var hasScanned = false

    var body: some View {
        NavigationStack {
            ZStack {
                switch cameraPermission {
                case .authorized:
                    CameraPreview(onCodeScanned: handleScan)
                        .ignoresSafeArea()

                    // Viewfinder overlay
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white, lineWidth: 2)
                            .frame(width: 250, height: 250)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.black.opacity(0.1))
                            )
                        Text("Point camera at QR code\ndisplayed on your Mac")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(.top, 16)
                        Spacer()
                    }

                case .denied, .restricted:
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(BalconyTheme.textSecondary)
                        Text("Camera Access Required")
                            .font(BalconyTheme.headingFont())
                            .foregroundStyle(BalconyTheme.textPrimary)
                        Text("Open Settings and allow camera access to scan QR codes.")
                            .multilineTextAlignment(.center)
                            .font(BalconyTheme.bodyFont())
                            .foregroundStyle(BalconyTheme.textSecondary)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings")
                                .font(BalconyTheme.bodyFont())
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, BalconyTheme.spacingXL)
                                .padding(.vertical, BalconyTheme.spacingMD)
                                .background(BalconyTheme.accent, in: Capsule())
                        }
                    }
                    .padding()

                case .notDetermined:
                    ProgressView("Requesting camera access...")

                @unknown default:
                    Text("Camera unavailable")
                        .foregroundStyle(BalconyTheme.textSecondary)
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                checkCameraPermission()
            }
        }
    }

    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraPermission = status

        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermission = granted ? .authorized : .denied
                }
            }
        }
    }

    private func handleScan(_ code: String) {
        guard !hasScanned else { return }
        hasScanned = true
        onScanned(code)
        dismiss()
    }
}

// MARK: - Camera Preview (UIViewControllerRepresentable)

/// Wraps AVCaptureSession for QR code scanning in SwiftUI.
private struct CameraPreview: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> CameraScannerController {
        let controller = CameraScannerController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraScannerController, context: Context) {}
}

/// UIViewController that manages AVCaptureSession for QR code detection.
private final class CameraScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeScanned: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }

    private func setupCaptureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              value.hasPrefix("balcony://") else {
            return
        }

        // Stop scanning after first valid QR code
        captureSession.stopRunning()
        onCodeScanned?(value)
    }
}
