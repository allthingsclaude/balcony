import Foundation

#if canImport(ActivityKit)
import ActivityKit

// MARK: - Activity Attributes

/// Defines the data model for Balcony's Live Activity — an aggregate dashboard
/// showing counts of sessions in each state.
@available(iOS 16.1, *)
public struct BalconySessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Sessions where Claude is actively running.
        public var workingCount: Int
        /// Sessions where Claude finished and is waiting for the next prompt.
        public var doneCount: Int
        /// Sessions that need user action (permission prompt or question).
        public var attentionCount: Int
        /// Total number of live sessions.
        public var totalCount: Int

        public init(workingCount: Int, doneCount: Int, attentionCount: Int, totalCount: Int) {
            self.workingCount = workingCount
            self.doneCount = doneCount
            self.attentionCount = attentionCount
            self.totalCount = totalCount
        }
    }

    public init() {}
}

#endif
