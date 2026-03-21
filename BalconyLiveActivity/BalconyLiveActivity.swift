import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Configuration

@available(iOS 16.1, *)
struct BalconyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BalconySessionAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
        } dynamicIsland: { context in
            let state = context.state

            return DynamicIsland {
                // MARK: Expanded

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 5) {
                        Image("BalconyLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)

                        Text("Balcony")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedCountsRow(state: state)
                        .padding(.top, 2)
                }
            } compactLeading: {
                Image("BalconyLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 4)
            } compactTrailing: {
                CompactTrailingView(state: state)
                    .padding(.trailing, 6)
            } minimal: {
                Image("BalconyLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
private struct LockScreenLiveActivityView: View {
    let state: BalconySessionAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            // Header: logo + brand name
            HStack(spacing: 6) {
                Image("BalconyLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)

                Text("Balcony")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)

                Spacer()

                Text("\(state.totalCount) session\(state.totalCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }

            // Counts row
            HStack(spacing: 0) {
                if state.workingCount > 0 {
                    CountColumn(
                        count: state.workingCount,
                        label: "Working",
                        color: Brand.light,
                        showPulse: true
                    )
                    .frame(maxWidth: .infinity)
                }
                if state.doneCount > 0 {
                    CountColumn(
                        count: state.doneCount,
                        label: "Finished",
                        color: Brand.medium,
                        showPulse: false
                    )
                    .frame(maxWidth: .infinity)
                }
                if state.attentionCount > 0 {
                    CountColumn(
                        count: state.attentionCount,
                        label: "Attention",
                        color: Brand.full,
                        showPulse: false
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .activityBackgroundTint(Brand.lockScreenBg)
    }
}

// MARK: - Count Column

/// Large number with a colored indicator and label below.
private struct CountColumn: View {
    let count: Int
    let label: String
    let color: Color
    let showPulse: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            HStack(spacing: 4) {
                if showPulse {
                    // Pulse ring for working state — concentric circles imply activity
                    PulseIndicator(color: color)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                }

                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }
}

/// A dot with an expanding ring — static "radar pulse" look that implies activity.
private struct PulseIndicator: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 12, height: 12)

            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 8, height: 8)

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
        }
    }
}

// MARK: - Dynamic Island Expanded Row

@available(iOS 16.1, *)
private struct ExpandedCountsRow: View {
    let state: BalconySessionAttributes.ContentState

    var body: some View {
        HStack(spacing: 0) {
            if state.workingCount > 0 {
                CompactCountPill(
                    count: state.workingCount,
                    label: "Working",
                    color: Brand.light,
                    showPulse: true
                )
                .frame(maxWidth: .infinity)
            }
            if state.doneCount > 0 {
                CompactCountPill(
                    count: state.doneCount,
                    label: "Finished",
                    color: Brand.medium,
                    showPulse: false
                )
                .frame(maxWidth: .infinity)
            }
            if state.attentionCount > 0 {
                CompactCountPill(
                    count: state.attentionCount,
                    label: "Attention",
                    color: Brand.full,
                    showPulse: false
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Compact pill for the Dynamic Island expanded bottom region.
private struct CompactCountPill: View {
    let count: Int
    let label: String
    let color: Color
    let showPulse: Bool

    var body: some View {
        HStack(spacing: 4) {
            if showPulse {
                PulseIndicator(color: color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }

            Text("\(count)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Compact Trailing

@available(iOS 16.1, *)
private struct CompactTrailingView: View {
    let state: BalconySessionAttributes.ContentState

    var body: some View {
        if state.attentionCount > 0 {
            countBadge(state.attentionCount, color: Brand.full)
        } else if state.doneCount > 0 {
            countBadge(state.doneCount, color: Brand.medium)
        } else {
            countBadge(state.workingCount, color: Brand.light)
        }
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Brand Colors (shades of #D97757)

private enum Brand {
    /// Lightest shade — for "Working" (active sessions)
    static let light = Color(red: 0.941, green: 0.682, blue: 0.604)   // #F0AE9A

    /// Medium shade — for "Finished" (awaiting next prompt)
    static let medium = Color(red: 0.894, green: 0.573, blue: 0.471)  // #E49278

    /// Full brand color — for "Attention" (needs user action)
    static let full = Color(red: 0.851, green: 0.467, blue: 0.341)    // #D97757

    /// Lock Screen dark background
    static let lockScreenBg = Color(red: 0.102, green: 0.098, blue: 0.082) // #1A1915

    /// Secondary text on dark background
    static let textSecondary = Color(red: 0.541, green: 0.529, blue: 0.502) // #8A8780
}
