#if canImport(ActivityKit)
import ActivityKit
import Foundation
import os

/// Manages a single Live Activity that shows an aggregate dashboard of all sessions.
@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private let logger = Logger(subsystem: "com.balcony.ios", category: "LiveActivityManager")
    private var currentActivity: Activity<BalconySessionAttributes>?

    // MARK: - Public API

    /// Start or update the Live Activity with the latest aggregate counts.
    /// Automatically starts a new activity if none exists, or updates the current one.
    func syncActivity(workingCount: Int, doneCount: Int, attentionCount: Int, totalCount: Int) {
        let state = BalconySessionAttributes.ContentState(
            workingCount: workingCount,
            doneCount: doneCount,
            attentionCount: attentionCount,
            totalCount: totalCount
        )

        if let activity = currentActivity, activity.activityState == .active {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        } else {
            startActivity(with: state)
        }
    }

    /// End the current Live Activity.
    func endActivity(dismissalPolicy: ActivityUIDismissalPolicy = .immediate) {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        Task {
            await activity.end(nil, dismissalPolicy: dismissalPolicy)
            logger.info("Ended Live Activity")
        }
    }

    /// Clean up any stale activities from previous app launches.
    func cleanupStaleActivities() {
        for activity in Activity<BalconySessionAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Private

    private func startActivity(with state: BalconySessionAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities not enabled by user")
            return
        }

        do {
            currentActivity = try Activity.request(
                attributes: BalconySessionAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            logger.info("Started Live Activity — \(state.totalCount) sessions")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }
}

#endif
