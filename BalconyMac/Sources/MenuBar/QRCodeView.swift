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
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
                    .foregroundStyle(.primary)
            } else {
                Text("Failed to generate QR code")
                    .foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                Text(pairingURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pairingURL, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy URL")
                .focusable(false)
            }
        }
    }

    /// Generate a QR code with transparent background.
    /// Uses CIColorInvert + CIMaskToAlpha to strip the white background,
    /// producing an alpha-only image that SwiftUI can tint via .renderingMode(.template).
    private func generateQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard var ciImage = filter.outputImage else { return nil }

        // Invert: black modules → white, white bg → black
        let invert = CIFilter(name: "CIColorInvert")!
        invert.setValue(ciImage, forKey: kCIInputImageKey)
        guard let inverted = invert.outputImage else { return nil }

        // MaskToAlpha: white → opaque, black → transparent
        let maskToAlpha = CIFilter(name: "CIMaskToAlpha")!
        maskToAlpha.setValue(inverted, forKey: kCIInputImageKey)
        guard let alphaImage = maskToAlpha.outputImage else { return nil }

        // Scale up for crisp rendering
        ciImage = alphaImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}
