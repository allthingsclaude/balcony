import Foundation
import UserNotifications
import os

/// Manages local and push notifications for session events.
final class NotificationManager: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.balcony.ios", category: "NotificationManager")

    override init() {
        super.init()
    }

    /// Request notification permissions.
    func requestPermissions() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    /// Schedule a local notification for a session event.
    func notifySessionEvent(sessionName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Balcony - \(sessionName)"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
}
