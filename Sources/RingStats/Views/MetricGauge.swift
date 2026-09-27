import SwiftUI

/// Fixed geometry for one metric tile. Every tile has the same zones in the
/// same order, so themes and metrics vary content, never layout:
///
/// 1. Visual zone (`visualSize` square): score ring, or icon above the value.
/// 2. Value baseline: every value sits on the baseline of a `valueFontSize`
///    reference line, whatever its own size, so mixed sizes still line up.
/// 3. Title line, `labelTopSpacing` below the visual zone.
/// 4. Detail line: score band, source day, sample age, or failure state.
enum MetricTileAnatomy {
    static let width = MetricStripLayout.itemWidth
    static let visualSize: CGFloat = 84
    static let scoreStrokeWidth: CGFloat = 8
    static let iconFontSize: CGFloat = 18
    static let iconValueSpacing: CGFloat = 3
    static let valueFontSize: CGFloat = 28
    static let compactValueFontSize: CGFloat = 18
    static let labelTopSpacing: CGFloat = 12
    static let titleDetailSpacing: CGFloat = 2
    static let titleFontSize: CGFloat = 12
    static let detailFontSize: CGFloat = 11

    static func valueFontSize(for metric: Metric) -> CGFloat {
        metric == .resilience ? compactValueFontSize : valueFontSize
    }
}

struct MetricGauge: View {
    let metric: Metric
    let reading: MetricReading?
    let pending: Bool
    let theme: AppTheme

    private var fraction: Double {
        Double(max(0, min(reading?.score ?? 0, 100))) / 100
    }

    private var displayValue: String { reading?.value ?? "—" }

    private var isStale: Bool { reading?.availability == .stale }

    /// The detail line. Both themes show the same text so neither loses meaning.
    /// A value from an earlier day says so instead of showing its band, because
    /// the date matters more than the label and both do not fit the tile.
    nonisolated static func detailText(
        reading: MetricReading?,
        pending: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let reading else { return pending ? "Updating…" : "No data" }
        if reading.availability == .stale { return "Not updated" }
        if let earlier = earlierDayLabel(sourceDay: reading.sourceDay, now: now, calendar: calendar) {
            return "From \(earlier)"
        }
        guard let observedAt = reading.observedAt else { return reading.detail ?? "No data" }
        let age = max(0, now.timeIntervalSince(observedAt))
        let compactAge = age < 3_600
            ? "\(max(1, Int(age / 60)))m ago"
            : "\(Int(age / 3_600))h ago"
        return [reading.detail, compactAge].compactMap { $0 }.joined(separator: " · ")
    }

    /// "yesterday" or a short date for a source day before today; nil for today.
    nonisolated static func earlierDayLabel(sourceDay: String?, now: Date, calendar: Calendar = .current) -> String? {
        guard let sourceDay, sourceDay != QueryDates.dayString(for: now, calendar: calendar) else { return nil }
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = calendar.timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: sourceDay) else { return sourceDay }
        if calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
            return "yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: day)
    }

    nonisolated static func accessibilityLabel(
        metric: Metric,
        reading: MetricReading?,
        pending: Bool,
        now: Date = Date()
    ) -> String {
        if pending { return "\(metric.title) updating" }
        guard let reading else { return "\(metric.title), no data" }
        let detail = reading.detail.map { ", \($0)" } ?? ""
        if reading.availability == .stale {
            let since = reading.lastFetchedAt.map {
                " from \(PopoverTimestampText.relativeAge(since: $0, now: now))"
            } ?? ""
            return "\(metric.title), \(reading.value)\(detail). Not updated; showing the last known value\(since)."
        }
        if let earlier = earlierDayLabel(sourceDay: reading.sourceDay, now: now) {
            return "\(metric.title), \(reading.value)\(detail), from \(earlier)"
        }
        return "\(metric.title), \(reading.value)\(detail)"
    }

    /// A value on the shared tile baseline. The hidden reference sets the
    /// baseline for every size, replacing per-metric offsets.
    private var baselineAlignedValue: some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .lastTextBaseline)) {
            Text("0")
                .font(.system(size: MetricTileAnatomy.valueFontSize, weight: .medium, design: .rounded))
                .hidden()
            Text(displayValue)
                .font(
                    .system(
                        size: MetricTileAnatomy.valueFontSize(for: metric),
                        weight: .medium,
                        design: .rounded
                    )
                )
                .monospacedDigit()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if pending {
                    ScoreLoadingSpinner(theme: theme)
                } else if theme == .landscape || !metric.isDailyScore {
                    VStack(spacing: MetricTileAnatomy.iconValueSpacing) {
                        Image(systemName: metric.symbolName)
                            .font(.system(size: MetricTileAnatomy.iconFontSize, weight: .regular))
                        baselineAlignedValue
                    }
                    .foregroundStyle(theme.primaryContent)
                } else {
                    if reading?.score != nil {
                        Circle()
                            .inset(by: MetricTileAnatomy.scoreStrokeWidth / 2)
                            .trim(from: 0, to: fraction)
                            .stroke(
                                theme.score,
                                style: StrokeStyle(
                                    lineWidth: MetricTileAnatomy.scoreStrokeWidth,
                                    lineCap: .round
                                )
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    baselineAlignedValue
                        .foregroundStyle(theme.primaryContent)
                }
            }
            .opacity(isStale ? 0.62 : 1)
            .frame(width: MetricTileAnatomy.visualSize, height: MetricTileAnatomy.visualSize)
            .accessibilityHidden(true)
            VStack(spacing: MetricTileAnatomy.titleDetailSpacing) {
                Text(metric.title)
                    .font(.system(size: MetricTileAnatomy.titleFontSize, weight: .semibold))
                Text(Self.detailText(reading: reading, pending: pending, now: Date()))
                    .font(.system(size: MetricTileAnatomy.detailFontSize))
                    .foregroundStyle(isStale ? theme.alert : theme.secondaryContent)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .padding(.top, MetricTileAnatomy.labelTopSpacing)
        }
        .frame(width: MetricTileAnatomy.width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(metric: metric, reading: reading, pending: pending))
    }
}

struct ScoreLoadingSpinner: View {
    let theme: AppTheme
    var diameter: CGFloat = 18
    var lineWidth: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(
                theme.primaryContent.opacity(theme == .landscape ? 0.72 : 0.56),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotating = true
                }
            }
    }
}

struct BatteryRow: View {
    let battery: BatteryRecord?
    let loading: Bool
    var stale = false
    var needsPermission = false
    let theme: AppTheme

    private var batteryStatus: String {
        guard let battery else { return "Battery" }
        return battery.level.map { "Battery \($0)%" } ?? "Battery —"
    }

    private var chargingStatus: String {
        guard let battery else {
            if needsPermission { return "Needs access" }
            return loading ? "Updating…" : "Unavailable"
        }
        return battery.charging == true || battery.inCharger == true ? "Charging" : "Not charging"
    }

    private var sampleAge: String? {
        guard let timestamp = battery?.timestamp else { return nil }
        return PopoverTimestampText.batterySample(timestamp: timestamp, now: Date())
    }

    var body: some View {
        HStack(spacing: 7) {
            BatteryStatusIcon(
                level: battery?.level,
                charging: battery?.charging == true || battery?.inCharger == true,
                theme: theme
            )
            HStack(spacing: 8) {
                Text(batteryStatus)
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryContent)
                Text(chargingStatus)
                    .foregroundStyle(theme.primaryContent.opacity(0.68))
                if stale {
                    Text("Not updated")
                        .foregroundStyle(theme.alert)
                } else if let sampleAge {
                    Text(sampleAge)
                        .foregroundStyle(theme.secondaryContent)
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .accessibilityElement(children: .combine)
    }
}

struct BatteryStatusIcon: View {
    let level: Int?
    let charging: Bool
    let theme: AppTheme

    private var symbolName: String {
        guard let level else { return "battery.0" }
        return switch level {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }

    private var tint: Color {
        if theme == .landscape { return .white }
        guard let level else { return Palette.alert }
        return level < 20 ? Palette.alert : Palette.signalBlue
    }

    var body: some View {
        ZStack {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .medium))
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .frame(width: 22, height: 20)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }
}
