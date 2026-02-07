import AppKit
import os

/// Manages the menu bar status item icon and state.
///
/// Connection state icon logic is now in `ConnectionManager.statusIconName`.
/// This class is retained for future use (e.g., custom NSStatusItem drawing).
@MainActor
final class StatusItemManager {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "StatusItem")
}
