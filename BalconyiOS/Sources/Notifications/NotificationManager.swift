import Foundation
import UserNotifications
import UIKit
import os

/// Manages local notifications for session events.
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let logger = Logger(subsystem: "com.balcony.ios", category: "NotificationManager")

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
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
    /// Only delivers when the app is not in the active foreground.
    func notifySessionEvent(sessionName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = sessionName
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

    // MARK: - UNUserNotificationCenterDelegate

    /// Suppress banners when the app is in the foreground (notifications are only
    /// scheduled when the app is inactive, but this guard catches race conditions).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }
}
