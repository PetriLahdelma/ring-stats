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

@Test func appThemesHaveStablePersistenceValues() {
    #expect(AppTheme.ringStats.rawValue == "ring-stats")
    #expect(AppTheme.landscape.rawValue == "landscape")
    #expect(AppTheme.resolve("oura-original") == .landscape)
    #expect(AppTheme.allCases.map(\.title) == ["Ring Stats", "Landscape"])
}
