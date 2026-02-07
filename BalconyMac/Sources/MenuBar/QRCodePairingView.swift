import SwiftUI
import BalconyShared

/// Sheet view that generates and displays a QR code for device pairing.
struct QRCodePairingView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var pairingURL: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            if let url = pairingURL {
                QRCodeView(pairingURL: url)
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            } else {
                ProgressView("Generating pairing code...")
            }

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 280, height: 320)
        .task {
            await generatePairingURL()
        }
    }

    private func generatePairingURL() async {
        do {
            pairingURL = try await connectionManager.generatePairingURL()
        } catch {
            errorMessage = "Failed to generate pairing code: \(error.localizedDescription)"
        }
    }
}
