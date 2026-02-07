import SwiftUI
import CoreImage.CIFilterBuiltins

/// Displays a QR code for device pairing.
struct QRCodeView: View {
    let pairingURL: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan with Balcony on iPhone")
                .font(.headline)

            if let image = generateQRCode(from: pairingURL) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
            } else {
                Text("Failed to generate QR code")
                    .foregroundStyle(.red)
            }

            Text(pairingURL)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}
