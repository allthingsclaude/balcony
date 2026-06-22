import Foundation
import IOKit

/// The Mac's stable hardware identifier (IOPlatformUUID), used as this device's identity in both
/// the pairing handshake and the Bonjour advertisement so the iPhone can match a discovered Mac to
/// a previously QR-paired record (and reuse its certificate pin).
enum MacDeviceID {
    /// Computed once and cached: a stable id for the lifetime of the process. Caching also means a
    /// (practically impossible) lookup failure can't yield a different fallback id on each call.
    static let current: String = {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(platformExpert) }

        if let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) {
            if let string = uuid.takeUnretainedValue() as? String {
                return string
            }
        }
        return "balcony-mac"
    }()
}
