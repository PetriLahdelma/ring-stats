import AppKit
import Foundation
import SwiftUI
import Testing
@testable import RingStats

@Test func scoreBandsMatchPublishedThresholds() {
    #expect(ScoreBand.label(for: 92) == "Optimal")
    #expect(ScoreBand.label(for: 85) == "Optimal")
    #expect(ScoreBand.label(for: 84) == "Good")
    #expect(ScoreBand.label(for: 70) == "Good")
    #expect(ScoreBand.label(for: 69) == "Fair")
    #expect(ScoreBand.label(for: 60) == "Fair")
    #expect(ScoreBand.label(for: 59) == "Pay attention")
    #expect(ScoreBand.label(for: nil) == "No data")
}

@Test func boundedRangeIncludesOnlyYesterdayThroughTomorrowBoundary() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-26T18:00:00Z"))
    let range = QueryDates.boundedRange(now: now, calendar: calendar)
    #expect(range.start == "2026-09-25")
    #expect(range.end == "2026-09-27")
}

@Test func batteryDecodesCurrentFields() throws {
    let json = #"{"data":[{"level":73,"charging":true,"in_charger":true,"timestamp":"2026-09-26T12:00:00+00:00"}]}"#.data(using: .utf8)!
    let envelope = try JSONDecoder().decode(BatteryEnvelope.self, from: json)
    #expect(envelope.data.first?.level == 73)
    #expect(envelope.data.first?.charging == true)
    #expect(envelope.data.first?.inCharger == true)
}

@Test func batterySampleAgeIsSeparateFromRefreshTime() {
    let now = Date(timeIntervalSince1970: 10_000)
    let sampledAt = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3_900))
    #expect(PopoverTimestampText.batterySample(timestamp: sampledAt, now: now) == "Sampled 1h ago")
    #expect(PopoverTimestampText.batterySample(timestamp: "invalid", now: now) == nil)
}

@Test func refreshStatusShowsSpinnerWhileRefreshing() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let status = try #require(
        PopoverTimestampText.refreshStatus(
            isRefreshing: true,
            outcome: .succeeded(at: now.addingTimeInterval(-600)),
            lastUpdatedAt: now.addingTimeInterval(-600),
            now: now,
            refreshInterval: 300
        )
    )
    #expect(status.label == "Refreshing…")
    #expect(status.showsSpinner)
    #expect(status.isVisible)
}

@Test func successConfirmationFadesAfterThreeSecondsWhileDataIsFresh() throws {
    let refreshedAt = Date(timeIntervalSince1970: 10_000)
    func status(after seconds: TimeInterval) throws -> RefreshStatusPresentation {
        try #require(
            PopoverTimestampText.refreshStatus(
                isRefreshing: false,
                outcome: .succeeded(at: refreshedAt),
                lastUpdatedAt: refreshedAt,
                now: refreshedAt.addingTimeInterval(seconds),
                refreshInterval: 300
            )
        )
    }
    #expect(try status(after: 0).isVisible)
    #expect(try status(after: 0).label == "Updated just now")
    #expect(try status(after: 2.9).isVisible)
    #expect(try !status(after: 3).isVisible)
    #expect(try !status(after: 299).isVisible)
    // VoiceOver still gets the age while nothing is drawn.
    #expect(try status(after: 120).accessibility == "Updated 2m ago")
}

@Test func agedDataKeepsItsAgeVisible() throws {
    let refreshedAt = Date(timeIntervalSince1970: 10_000)
    let status = try #require(
        PopoverTimestampText.refreshStatus(
            isRefreshing: false,
            outcome: .succeeded(at: refreshedAt),
            lastUpdatedAt: refreshedAt,
            now: refreshedAt.addingTimeInterval(720),
            refreshInterval: 300
        )
    )
    #expect(status.isVisible)
    #expect(status.label == "Updated 12m ago")
    #expect(status.tone == .neutral)
}

@Test func failuresStayVisibleInAlertTone() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let failed = try #require(
        PopoverTimestampText.refreshStatus(
            isRefreshing: false,
            outcome: .failed(at: now),
            lastUpdatedAt: now.addingTimeInterval(-3_900),
            now: now.addingTimeInterval(60),
            refreshInterval: 300
        )
    )
    #expect(failed.label == "Update failed · 1h ago")
    #expect(failed.tone == .alert)
    #expect(failed.isVisible)

    let partial = try #require(
        PopoverTimestampText.refreshStatus(
            isRefreshing: false,
            outcome: .partial(at: now),
            lastUpdatedAt: now,
            now: now.addingTimeInterval(60),
            refreshInterval: 300
        )
    )
    #expect(partial.label == "Some stats not updated")
    #expect(partial.tone == .alert)
    #expect(partial.isVisible)
}

@Test func noStatusBeforeTheFirstRefresh() {
    #expect(
        PopoverTimestampText.refreshStatus(
            isRefreshing: false,
            outcome: .none,
            lastUpdatedAt: nil,
            now: Date(),
            refreshInterval: 300
        ) == nil
    )
}

@Test func staleTileSaysSoInTextAndToVoiceOver() {
    let stale = MetricReading(value: "80", detail: "Good", score: 80).markedStale()
    #expect(MetricGauge.detailText(reading: stale, pending: false, now: Date()) == "Not updated")
    #expect(
        MetricGauge.accessibilityLabel(metric: .activity, reading: stale, pending: false)
            == "Activity, 80, Good. Not updated; showing the last known value."
    )
}

@Test func metricStripReportsOverflowOnlyAtEdgesWithHiddenStats() {
    // Six tiles need 6 * 92 + 5 * 16 = 632 pt.
    let content: CGFloat = 632
    #expect(
        MetricStripLayout.overflow(contentWidth: content, viewportWidth: 700, contentMinX: 0)
            == MetricStripOverflow(leading: false, trailing: false)
    )
    #expect(
        MetricStripLayout.overflow(contentWidth: content, viewportWidth: 372, contentMinX: 0)
            == MetricStripOverflow(leading: false, trailing: true)
    )
    #expect(
        MetricStripLayout.overflow(contentWidth: content, viewportWidth: 372, contentMinX: -130)
            == MetricStripOverflow(leading: true, trailing: true)
    )
    #expect(
        MetricStripLayout.overflow(contentWidth: content, viewportWidth: 372, contentMinX: -260)
            == MetricStripOverflow(leading: true, trailing: false)
    )
}

@Test func tokenExpiryUsesResponseLifetime() {
    let now = Date(timeIntervalSince1970: 1_000)
    let response = TokenResponse(accessToken: "access", refreshToken: "refresh", expiresIn: 3600)
    let token = response.token(now: now)
    #expect(token.expiresAt == Date(timeIntervalSince1970: 4_600))
}

@Test func metricEndpointsAreStable() {
    #expect(Metric.readiness.dailyScoreEndpoint == "daily_readiness")
    #expect(Metric.sleep.dailyScoreEndpoint == "daily_sleep")
    #expect(Metric.activity.dailyScoreEndpoint == "daily_activity")
    #expect(Metric.heartRate.dailyScoreEndpoint == nil)
    #expect(Metric.stress.dailyScoreEndpoint == nil)
    #expect(Metric.resilience.dailyScoreEndpoint == nil)
    #expect(Metric.defaultVisible == [.readiness, .sleep, .activity, .heartRate, .stress])
}

@Test @MainActor func finishedMetricWithoutReadingDoesNotRemainPending() {
    #expect(MenuPopoverView.metricIsPending(reading: nil, loading: true))
    #expect(!MenuPopoverView.metricIsPending(reading: nil, loading: false))
    let reading = MetricReading(value: "72", detail: "Good", score: 72)
    #expect(!MenuPopoverView.metricIsPending(reading: reading, loading: true))
}

@Test @MainActor func popoverShellMeasuresToFiniteContentHeight() {
    let geometry = PopoverGeometryModel()
    let controller = NSHostingController(
        rootView: MenuPopoverShell(geometry: geometry) {
            Color.clear.frame(width: 420, height: 250)
        }
    )
    let size = controller.sizeThatFits(in: NSSize(width: 420, height: 800))
    #expect(size.width == 420)
    #expect(size.height == 261)
}

@Test func popoverWidthClampsToSupportedRange() {
    #expect(PopoverLayout.defaultWidth == 680)
    #expect(PopoverLayout.clampedWidth(300, availableWidth: 1_000) == 420)
    #expect(PopoverLayout.clampedWidth(640, availableWidth: 1_000) == 640)
    #expect(PopoverLayout.clampedWidth(1_000, availableWidth: 1_000) == 840)
    #expect(PopoverLayout.clampedWidth(800, availableWidth: 700) == 700)
}

@Test @MainActor func statusPopoverSupportsNativeHorizontalResize() {
    let panel = StatusPopoverPanel()
    #expect(panel.styleMask.contains(.resizable))
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
}

@Test @MainActor func statusPopoverEscapeInvokesCancellationHandler() {
    let panel = StatusPopoverPanel()
    var cancellationCount = 0
    panel.onCancel = { cancellationCount += 1 }

    #expect(panel.canBecomeKey)
    panel.cancelOperation(nil)

    #expect(cancellationCount == 1)
}

@Test func extendedMetricPayloadsDecodePublishedFields() throws {
    let heartJSON = #"{"data":[{"timestamp":"2026-09-26T12:00:00Z","bpm":80,"source":"awake"}]}"#.data(using: .utf8)!
    let stressJSON = #"{"data":[{"day":"2026-09-26","day_summary":"normal","recovery_high":1200,"stress_high":900}]}"#.data(using: .utf8)!
    let resilienceJSON = #"{"data":[{"day":"2026-09-26","level":"solid"}]}"#.data(using: .utf8)!

    let heart = try JSONDecoder().decode(HeartRateEnvelope.self, from: heartJSON)
    let stress = try JSONDecoder().decode(DailyStressEnvelope.self, from: stressJSON)
    let resilience = try JSONDecoder().decode(DailyResilienceEnvelope.self, from: resilienceJSON)

    #expect(heart.data.first?.bpm == 80)
    #expect(stress.data.first?.stressHigh == 900)
    #expect(stress.data.first?.daySummary == "normal")
    #expect(resilience.data.first?.level == "solid")
}

@Test func metricConfigurationPersistsOrderAndVisibility() {
    var configuration = MetricConfiguration.default
    configuration.order.swapAt(0, 1)
    configuration.hidden.insert(.stress)
    let decoded = MetricConfiguration.decode(configuration.encoded)

    #expect(decoded.order.first == .sleep)
    #expect(decoded.hidden.contains(.stress))
    #expect(decoded.hidden.contains(.resilience))
}

@Test func metricConfigurationSupportsPopoverDragOrdering() {
    var configuration = MetricConfiguration.default
    configuration.hidden.insert(.stress)

    let movedBefore = configuration.moving(.activity, relativeTo: .readiness, after: false)
    #expect(movedBefore.order.prefix(3) == [.activity, .readiness, .sleep])
    #expect(movedBefore.hidden.contains(.stress))

    let movedAfter = movedBefore.moving(.activity, relativeTo: .sleep, after: true)
    #expect(movedAfter.order.prefix(3) == [.readiness, .sleep, .activity])
    #expect(movedAfter.hidden.contains(.stress))
}

@Test func metricConfigurationSupportsNativeListReordering() {
    var configuration = MetricConfiguration.default
    configuration.hidden.insert(.stress)

    let firstToLast = configuration.moving(
        fromOffsets: IndexSet(integer: 0),
        toOffset: configuration.order.count
    )
    #expect(firstToLast.order.last == .readiness)
    #expect(firstToLast.hidden == configuration.hidden)

    let lastToFirst = configuration.moving(
        fromOffsets: IndexSet(integer: configuration.order.count - 1),
        toOffset: 0
    )
    #expect(lastToFirst.order.first == .resilience)
    #expect(lastToFirst.hidden == configuration.hidden)

    let multiple = configuration.moving(
        fromOffsets: IndexSet([1, 2]),
        toOffset: 5
    )
    #expect(multiple.order == [.readiness, .heartRate, .stress, .sleep, .activity, .resilience])
    #expect(multiple.hidden == configuration.hidden)
}

@Test func metricConfigurationNativeReorderingRejectsInvalidAndNoOpMoves() {
    let configuration = MetricConfiguration.default
    #expect(configuration.moving(fromOffsets: [], toOffset: 0) == configuration)
    #expect(configuration.moving(fromOffsets: IndexSet(integer: 99), toOffset: 0) == configuration)
    #expect(configuration.moving(fromOffsets: IndexSet(integer: 0), toOffset: 99) == configuration)
    #expect(configuration.moving(.readiness, by: -1) == configuration)
    #expect(configuration.moving(.resilience, by: 1) == configuration)
    #expect(configuration.moving(.sleep, by: 0) == configuration)
}

@Test func metricReorderCapabilitiesExposeOnlyPossibleBoundaryActions() throws {
    let configuration = MetricConfiguration.default
    let first = try #require(configuration.reorderCapabilities(for: .readiness))
    #expect(first.position == 1)
    #expect(first.total == configuration.order.count)
    #expect(!first.canMoveUp)
    #expect(first.canMoveDown)

    let middle = try #require(configuration.reorderCapabilities(for: .activity))
    #expect(middle.canMoveUp)
    #expect(middle.canMoveDown)

    let last = try #require(configuration.reorderCapabilities(for: .resilience))
    #expect(last.position == configuration.order.count)
    #expect(last.canMoveUp)
    #expect(!last.canMoveDown)

    let moved = configuration.moving(.readiness, by: 1)
    let movedReadiness = try #require(moved.reorderCapabilities(for: .readiness))
    #expect(movedReadiness.position == 2)
    #expect(movedReadiness.canMoveUp)
}

@Test func metricReorderSessionPreviewsMovementWithoutMutatingStoredConfiguration() {
    let configuration = MetricConfiguration.default
    var session = MetricReorderSession(source: .activity, configuration: configuration)
    let translationPastHeartRate = MetricStripLayout.centerX(at: 3)
        + MetricStripLayout.reorderHysteresis
        - MetricStripLayout.centerX(at: 2)
        + 0.5

    let didMove = session.update(translationX: translationPastHeartRate)
    #expect(didMove)
    #expect(
        session.provisional.visibleMetrics
            == [.readiness, .sleep, .heartRate, .activity, .stress]
    )
    #expect(configuration.visibleMetrics == Metric.defaultVisible)
    #expect(session.original == configuration.normalized)
}

@Test func metricReorderSessionMovesOnlyAfterCrossingANeighborCenter() {
    let configuration = MetricConfiguration.default
    let sourceCenter = MetricStripLayout.centerX(at: 1)
    let leftThreshold = MetricStripLayout.centerX(at: 0)
        - MetricStripLayout.reorderHysteresis
    let beforeThreshold = leftThreshold - sourceCenter + 0.5
    let afterThreshold = leftThreshold - sourceCenter - 0.5

    var beforeMidpoint = MetricReorderSession(source: .sleep, configuration: configuration)
    let movedBeforeMidpoint = beforeMidpoint.update(translationX: beforeThreshold)
    #expect(!movedBeforeMidpoint)
    #expect(beforeMidpoint.provisional == configuration.normalized)

    var atMidpoint = MetricReorderSession(source: .sleep, configuration: configuration)
    let movedAtMidpoint = atMidpoint.update(translationX: afterThreshold)
    #expect(movedAtMidpoint)
    #expect(atMidpoint.provisional.visibleMetrics.prefix(2) == [.sleep, .readiness])
}

@Test func metricReorderSessionCanMoveAcrossMultipleNeighborsWithoutJitter() {
    let configuration = MetricConfiguration.default
    var session = MetricReorderSession(source: .readiness, configuration: configuration)
    let translationPastStress = MetricStripLayout.centerX(at: 4)
        + MetricStripLayout.reorderHysteresis
        - MetricStripLayout.centerX(at: 0)
        + 0.5

    let movedAcrossStrip = session.update(translationX: translationPastStress)
    #expect(movedAcrossStrip)
    #expect(session.provisional.visibleMetrics.last == .readiness)
    let repeatedUpdateMoved = session.update(translationX: translationPastStress)
    #expect(!repeatedUpdateMoved)
}

@Test func metricReorderSessionRestoresItsOriginalPreview() {
    let configuration = MetricConfiguration.default
    var session = MetricReorderSession(source: .activity, configuration: configuration)
    let translationPastHeartRate = MetricStripLayout.centerX(at: 3)
        + MetricStripLayout.reorderHysteresis
        - MetricStripLayout.centerX(at: 2)
        + 0.5

    let didMove = session.update(translationX: translationPastHeartRate)
    #expect(didMove)
    let didReset = session.resetPreview()
    #expect(didReset)
    #expect(session.provisional == configuration.normalized)
    let repeatedReset = session.resetPreview()
    #expect(!repeatedReset)
}

@Test func metricReorderOffsetsKeepSourceDirectAndShiftOnlySiblings() {
    var session = MetricReorderSession(source: .readiness, configuration: .default)
    let translation = MetricStripLayout.centerX(at: 3)
        + MetricStripLayout.reorderHysteresis
        - MetricStripLayout.centerX(at: 0)
        + 0.5
    let moved = session.update(translationX: translation)
    #expect(moved)

    #expect(session.offsetX(for: .readiness, sourceTranslationX: translation) == translation)
    #expect(session.offsetX(for: .readiness, sourceTranslationX: 37) == 37)
    #expect(session.offsetX(for: .sleep, sourceTranslationX: translation) == -MetricStripLayout.stride)
    #expect(session.offsetX(for: .activity, sourceTranslationX: translation) == -MetricStripLayout.stride)
    #expect(session.offsetX(for: .heartRate, sourceTranslationX: translation) == -MetricStripLayout.stride)
    #expect(session.offsetX(for: .stress, sourceTranslationX: translation) == 0)
    #expect(session.releaseTargetOffsetX == 3 * MetricStripLayout.stride)
}

@Test func metricReorderOffsetsRestoreAfterReverseCrossing() {
    var session = MetricReorderSession(source: .activity, configuration: .default)
    let moveRight = MetricStripLayout.centerX(at: 4)
        + MetricStripLayout.reorderHysteresis
        - MetricStripLayout.centerX(at: 2)
        + 0.5
    let movedRight = session.update(translationX: moveRight)
    #expect(movedRight)
    #expect(session.offsetX(for: .stress, sourceTranslationX: moveRight) == -MetricStripLayout.stride)

    let moveBack = -MetricStripLayout.reorderHysteresis - 10.5
    let movedBack = session.update(translationX: moveBack)
    #expect(movedBack)
    #expect(session.provisional == session.original)
    #expect(session.offsetX(for: .stress, sourceTranslationX: moveBack) == 0)
    #expect(session.releaseTargetOffsetX == 0)
}

@Test func reducedMotionReorderSettlementIsImmediate() {
    #expect(MetricReorderMotion.duration(reduceMotion: true) == 0)
    #expect(MetricReorderMotion.duration(reduceMotion: false) == 0.16)
}

@Test func validReorderReleaseExposesCommitBeforeVisualSettlement() {
    var session = MetricReorderSession(source: .activity, configuration: .default)
    let translation = MetricStripLayout.centerX(at: 4)
        + MetricStripLayout.reorderHysteresis
        - MetricStripLayout.centerX(at: 2)
        + 0.5
    let moved = session.update(translationX: translation)
    #expect(moved)

    let valid = session.resolution(isValidRelease: true)
    #expect(valid.committedConfiguration == session.provisional)
    #expect(valid.targetOffsetX == 2 * MetricStripLayout.stride)

    let invalid = session.resolution(isValidRelease: false)
    #expect(invalid.committedConfiguration == nil)
    #expect(invalid.targetOffsetX == 0)
}

@Test func metricStripContainmentRejectsHorizontalAndVerticalExits() {
    let size = CGSize(width: 632, height: 126)

    #expect(MetricStripLayout.contains(CGPoint(x: 316, y: 63), in: size))
    #expect(!MetricStripLayout.contains(CGPoint(x: -1, y: 63), in: size))
    #expect(!MetricStripLayout.contains(CGPoint(x: 633, y: 63), in: size))
    #expect(!MetricStripLayout.contains(CGPoint(x: 316, y: -1), in: size))
    #expect(!MetricStripLayout.contains(CGPoint(x: 316, y: 127), in: size))
}

@Test func appThemesHaveStablePersistenceValues() {
    #expect(AppTheme.ringStats.rawValue == "ring-stats")
    #expect(AppTheme.landscape.rawValue == "landscape")
    #expect(AppTheme.resolve("oura-original") == .landscape)
    #expect(AppTheme.allCases.map(\.title) == ["Ring Stats", "Landscape"])
}

@Test @MainActor func everyTileDetailFitsTheTileWithoutTruncation() {
    // The detail line is limited to one line, so anything wider than the tile
    // is silently cut off. Measure every string the app can put there.
    let font = NSFont.systemFont(ofSize: MetricTileAnatomy.detailFontSize)
    let now = Date(timeIntervalSince1970: 1_790_467_200)
    var details: [String] = [60, 70, 85, 40].map { ScoreBand.label(for: $0) }
    details += ["Updating…", "No data", "Not updated", "Long-term", "High stress"]
    details += ["Restored", "Normal", "Stressful"]
    details += [nil, .insufficientScope, .timedOut].compactMap { OuraAPI.placeholder(for: $0).detail }
    details += [59, 3_540, 82_800].map { age in
        MetricGauge.detailText(
            reading: MetricReading(value: "58", detail: "bpm", score: nil, observedAt: now.addingTimeInterval(-Double(age))),
            pending: false,
            now: now
        )
    }
    details += [1, 6].map { daysAgo in
        let day = QueryDates.dayString(for: now.addingTimeInterval(-86_400 * Double(daysAgo)))
        return MetricGauge.detailText(
            reading: MetricReading(value: "72", detail: "Pay attention", score: 40, sourceDay: day),
            pending: false,
            now: now
        )
    }
    for detail in details {
        let width = (detail as NSString).size(withAttributes: [.font: font]).width
        #expect(width <= MetricTileAnatomy.width, "\"\(detail)\" is \(width) pt wide")
    }
}

@Test func earlierSourceDaysAreLabelledRelativeToToday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Helsinki"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-26T09:00:00Z"))
    #expect(MetricGauge.earlierDayLabel(sourceDay: "2026-09-26", now: now, calendar: calendar) == nil)
    #expect(MetricGauge.earlierDayLabel(sourceDay: "2026-09-25", now: now, calendar: calendar) == "yesterday")
    let reading = MetricReading(value: "72", detail: "Good", score: 72, sourceDay: "2026-09-25")
    #expect(MetricGauge.detailText(reading: reading, pending: false, now: now, calendar: calendar) == "From yesterday")
}
