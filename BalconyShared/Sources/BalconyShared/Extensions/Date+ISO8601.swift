import Foundation

extension Date {
    /// Format date as ISO 8601 string.
    public var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// Parse an ISO 8601 string into a Date.
    public static func fromISO8601(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
