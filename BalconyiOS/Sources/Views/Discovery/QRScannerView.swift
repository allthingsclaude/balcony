import SwiftUI
import AVFoundation

/// Camera-based QR code scanner for device pairing.
struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    var onScanned: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack {
                // TODO: Implement AVCaptureSession-based QR scanner
                Text("Point camera at QR code\ndisplayed on your Mac")
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .padding()

                RoundedRectangle(cornerRadius: 12)
                    .stroke(.blue, lineWidth: 2)
                    .frame(width: 250, height: 250)
                    .overlay {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
