import Foundation

/// Identity information for a paired device.
public struct DeviceInfo: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let platform: DevicePlatform
    public let publicKeyFingerprint: String

    public init(
        id: String,
        name: String,
        platform: DevicePlatform,
        publicKeyFingerprint: String
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.publicKeyFingerprint = publicKeyFingerprint
    }
}

/// Platform type for a device.
public enum DevicePlatform: String, Codable, Sendable {
    case macOS
    case iOS
}
