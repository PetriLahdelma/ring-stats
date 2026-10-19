import AppKit
import SwiftUI
import RingStatsCore

/// What the top-right status shows. `label` stays populated while hidden so
/// the text can fade out instead of vanishing, and `accessibility` is always
/// available to VoiceOver even when nothing is drawn.
struct RefreshStatusPresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case alert
    }

    let label: String
    let accessibility: String
    let isVisible: Bool
    let showsSpinner: Bool
    let tone: Tone
    /// Whether the status offers to run a refresh when clicked.
    var isRetryable = false
}

enum PopoverTimestampText {
    /// How long "Updated just now" stays after a successful refresh.
    static let confirmationDuration: TimeInterval = 3

    static func refreshStatus(
        isRefreshing: Bool,
        outcome: RefreshOutcome,
        lastUpdatedAt: Date?,
        now: Date,
        refreshInterval: TimeInterval,
        nothingPublished: Bool = false
    ) -> RefreshStatusPresentation? {
        if isRefreshing {
            return RefreshStatusPresentation(
                label: "Refreshing…",
                accessibility: "Refreshing stats",
                isVisible: true,
                showsSpinner: true,
                tone: .neutral
            )
        }
        switch outcome {
        case .none:
            return nil
        case .failed:
            guard let lastUpdatedAt else {
                return RefreshStatusPresentation(
                    label: "Update failed · Retry",
                    accessibility: "Update failed. Retry.",
                    isVisible: true,
                    showsSpinner: false,
                    tone: .alert,
                    isRetryable: true
                )
            }
            let age = relativeAge(since: lastUpdatedAt, now: now)
            return RefreshStatusPresentation(
                label: "Update failed · \(age) · Retry",
                accessibility: "Update failed. Showing values from \(age). Retry.",
                isVisible: true,
                showsSpinner: false,
                tone: .alert,
                isRetryable: true
            )
        case .partial(let at):
            let age = relativeAge(since: at, now: now)
            return RefreshStatusPresentation(
                label: "Some stats stale · \(age) · Retry",
                accessibility: "Updated \(age). Some stats could not be updated and show their last known values. Retry.",
                isVisible: true,
                showsSpinner: false,
                tone: .alert,
                isRetryable: true
            )
        case .succeeded(let at):
            // Always visible: the age is the freshness promise, and hiding it
            // between the confirmation and the next refresh hid it most of
            // the time.
            // A successful fetch that returned no scores must not read as
            // "updated" above a strip of empty tiles.
            let label = nothingPublished
                ? "Checked \(relativeAge(since: at, now: now)) · nothing published yet"
                : "Updated \(relativeAge(since: at, now: now))"
            return RefreshStatusPresentation(
                label: label,
                accessibility: label,
                isVisible: true,
                showsSpinner: false,
                tone: .neutral,
                isRetryable: true
            )
        }
    }

    static func relativeAge(since date: Date, now: Date) -> String {
        let age = max(0, now.timeIntervalSince(date))
        return switch age {
        case ..<60: "just now"
        case ..<3_600: "\(Int(age / 60))m ago"
        case ..<86_400: "\(Int(age / 3_600))h ago"
        default: "\(Int(age / 86_400))d ago"
        }
    }
}

/// What VoiceOver says when a refresh someone asked for finishes. The status
/// label changes silently, so without this a VoiceOver user gets no answer.
enum RefreshAnnouncement {
    static func text(for outcome: RefreshOutcome) -> String? {
        switch outcome {
        case .none: nil
        case .succeeded: "Stats updated"
        case .partial: "Some stats could not be updated and show their last known values"
        case .failed: "Update failed"
        }
    }

    @MainActor static func post(for outcome: RefreshOutcome) {
        guard let text = text(for: outcome) else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// The top-right refresh status. It redraws every second so relative ages
/// stay truthful while the popover is open.
struct RefreshStatusView: View {
    @EnvironmentObject private var model: AppViewModel
    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.popoverIsPresented) private var isPresented
    let theme: AppTheme
    var nothingPublished = false
    var requestRefresh: () -> Void = {}

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isPresented)) { context in
            if let status = PopoverTimestampText.refreshStatus(
                isRefreshing: model.isRefreshing,
                outcome: model.lastRefreshOutcome,
                lastUpdatedAt: model.lastUpdatedAt,
                now: context.date,
                refreshInterval: model.refreshInterval,
                nothingPublished: nothingPublished
            ) {
                // The status is the retry control: clicking "Updated 2m ago"
                // refreshes, and a failure says "Retry" in the line itself.
                Button(action: requestRefresh) {
                    HStack(spacing: 5) {
                        if status.showsSpinner {
                            ScoreLoadingSpinner(theme: theme, diameter: (9 * textScale).rounded(), lineWidth: 1.5)
                        }
                        // "Retry" is the action, so it is the only word that
                        // looks like one.
                        statusText(status.label)
                            .scaledFont(size: 10)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(status.tone == .alert ? theme.alert : theme.secondaryContent)
                    .frame(maxWidth: 300, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .linkCursor(status.isRetryable)
                .keyboardActivatable(theme: theme, cornerRadius: 4, action: requestRefresh)
                .disabled(!status.isRetryable)
                .accessibilityLabel(status.accessibility)
                .accessibilityHint(status.isRetryable ? "Refreshes the stats now" : "")
                .accessibilitySortPriority(1)
            }
        }
    }
}

private func statusText(_ label: String) -> Text {
    let action = " · Retry"
    guard label.hasSuffix(action) else { return Text(label) }
    return Text(String(label.dropLast(action.count))) + Text(action).fontWeight(.semibold).underline()
}

extension View {
    /// A pointing hand over a clickable line of text, where macOS supports it.
    @ViewBuilder
    func linkCursor(_ active: Bool) -> some View {
        if #available(macOS 15, *), active {
            pointerStyle(.link)
        } else {
            self
        }
    }
}
