import Foundation

/// Identity information for a paired device.
public struct DeviceInfo: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let platform: DevicePlatform
    /// SHA-256 (base64) pin of the peer's self-signed TLS certificate, captured at QR pairing.
    /// Empty until the device has been paired via QR.
    public let certFingerprint: String

    public init(
        id: String,
        name: String,
        platform: DevicePlatform,
        certFingerprint: String
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.certFingerprint = certFingerprint
    }
}

/// Platform type for a device.
public enum DevicePlatform: String, Codable, Sendable {
    case macOS
    case iOS
}
