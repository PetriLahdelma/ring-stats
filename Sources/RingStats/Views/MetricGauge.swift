import SwiftUI
import RingStatsCore
import RingStatsOura

/// Fixed geometry for one metric tile. Every tile has the same zones in the
/// same order, so themes and metrics vary content, never layout:
///
/// 1. Visual zone (`visualSize` square): score ring, or icon above the value.
/// 2. Value baseline: every value sits on the baseline of a `valueFontSize`
///    reference line, whatever its own size, so mixed sizes still line up.
/// 3. Title line, `labelTopSpacing` below the visual zone.
/// 4. Detail line: score band, source day, sample age, or failure state.
struct MetricTileAnatomy: Equatable, Sendable {
    static let standard = MetricTileAnatomy(scale: 1)

    let scale: CGFloat

    private func scaled(_ value: CGFloat) -> CGFloat { (value * scale).rounded() }

    var width: CGFloat { MetricStripLayout(scale: scale).itemWidth }
    var visualSize: CGFloat { scaled(84) }
    var scoreStrokeWidth: CGFloat { scaled(8) }
    var iconFontSize: CGFloat { scaled(18) }
    var iconValueSpacing: CGFloat { scaled(3) }
    var valueFontSize: CGFloat { scaled(28) }
    var compactValueFontSize: CGFloat { scaled(18) }
    var labelTopSpacing: CGFloat { scaled(12) }
    var titleDetailSpacing: CGFloat { scaled(2) }
    var titleFontSize: CGFloat { scaled(12) }
    var detailFontSize: CGFloat { scaled(11) }

    func valueFontSize(for metric: Metric) -> CGFloat {
        metric == .resilience ? compactValueFontSize : valueFontSize
    }

    static var width: CGFloat { standard.width }
    static var detailFontSize: CGFloat { standard.detailFontSize }
    static var valueFontSize: CGFloat { standard.valueFontSize }
}

struct MetricGauge: View {
    let metric: Metric
    let reading: MetricReading?
    let pending: Bool
    let theme: AppTheme
    @Environment(\.textScale) private var textScale

    private var anatomy: MetricTileAnatomy { MetricTileAnatomy(scale: textScale) }

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
                .font(.system(size: anatomy.valueFontSize, weight: .medium, design: .rounded))
                .hidden()
            Text(displayValue)
                .font(
                    .system(
                        size: anatomy.valueFontSize(for: metric),
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
                    ScoreLoadingSpinner(theme: theme, diameter: (18 * textScale).rounded())
                } else if theme == .landscape || !metric.isDailyScore {
                    VStack(spacing: anatomy.iconValueSpacing) {
                        Image(systemName: metric.symbolName)
                            .font(.system(size: anatomy.iconFontSize, weight: .regular))
                        baselineAlignedValue
                    }
                    .foregroundStyle(theme.primaryContent)
                } else {
                    if reading?.score != nil {
                        Circle()
                            .inset(by: anatomy.scoreStrokeWidth / 2)
                            .trim(from: 0, to: fraction)
                            .stroke(
                                theme.score,
                                style: StrokeStyle(
                                    lineWidth: anatomy.scoreStrokeWidth,
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
            .frame(width: anatomy.visualSize, height: anatomy.visualSize)
            .accessibilityHidden(true)
            VStack(spacing: anatomy.titleDetailSpacing) {
                Text(metric.title)
                    .font(.system(size: anatomy.titleFontSize, weight: .semibold))
                Text(Self.detailText(reading: reading, pending: pending, now: Date()))
                    .font(.system(size: anatomy.detailFontSize))
                    .foregroundStyle(isStale ? theme.alert : theme.secondaryContent)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .padding(.top, anatomy.labelTopSpacing)
        }
        .frame(width: anatomy.width)
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
    let battery: BatteryReading?
    let loading: Bool
    var stale = false
    var needsPermission = false
    let theme: AppTheme

    private var batteryStatus: String {
        guard let battery else { return "Battery" }
        return battery.level.map { "Battery \($0)%" } ?? "Battery —"
    }

    /// The visible text beside the level. Not charging is the usual state, so
    /// it shows nothing; the bolt in the icon and this text mark the exception.
    private var chargingStatus: String? {
        guard let battery else {
            if needsPermission { return "Needs access" }
            return loading ? "Updating…" : "Unavailable"
        }
        return Self.chargeState(for: battery)
    }

    /// "Charged" once a ring in its charger reaches 100%, "Charging" before
    /// that, and nothing when it is not charging.
    static func chargeState(for battery: BatteryReading) -> String? {
        guard battery.isCharging else { return nil }
        return (battery.level ?? 0) >= 100 ? "Charged" : "Charging"
    }

    /// VoiceOver cannot see the bolt, so it always hears the charging state.
    var accessibilityDescription: String {
        var parts = [batteryStatus, chargingStatus ?? "Not charging"]
        if stale {
            parts.append("Not updated")
        }
        return parts.joined(separator: ", ")
    }

    private func statusLine(showsCharging: Bool, showsTrailing: Bool) -> some View {
        HStack(spacing: 8) {
            Text(batteryStatus)
                .monospacedDigit()
                .foregroundStyle(theme.primaryContent)
            if showsCharging, let chargingStatus {
                Text(chargingStatus)
                    .foregroundStyle(theme.primaryContent.opacity(0.68))
            }
            if showsTrailing, stale {
                Text("Not updated")
                    .foregroundStyle(theme.alert)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    var body: some View {
        HStack(spacing: 7) {
            BatteryStatusIcon(
                level: battery?.level,
                charging: battery?.isCharging == true,
                theme: theme
            )
            // Never wrap: drop the least important text when space is tight.
            // VoiceOver still hears everything through the label below.
            ViewThatFits(in: .horizontal) {
                statusLine(showsCharging: true, showsTrailing: true)
                statusLine(showsCharging: true, showsTrailing: false)
                statusLine(showsCharging: false, showsTrailing: false)
            }
        }
        .scaledFont(size: 12, weight: .medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}

struct BatteryStatusIcon: View {
    let level: Int?
    let charging: Bool
    let theme: AppTheme
    @Environment(\.textScale) private var textScale

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
        // Alert red is too light for 3:1 on the pastel foil, so Holographic
        // uses its darker text red for the icon too.
        let low = theme == .holographic ? theme.alert : Palette.alert
        guard let level else { return low }
        return level < 20 ? low : theme.action
    }

    var body: some View {
        ZStack {
            Image(systemName: symbolName)
                .scaledFont(size: 17, weight: .medium)
            if charging {
                // Cut a slightly larger bolt out of the fill, then draw the
                // bolt inside the gap, as macOS does, so it stays visible at
                // every level instead of vanishing into a full battery.
                Image(systemName: "bolt.fill")
                    .scaledFont(size: 10, weight: .black)
                    .offset(x: -1)
                    .blendMode(.destinationOut)
                Image(systemName: "bolt.fill")
                    .scaledFont(size: 8, weight: .bold)
                    .offset(x: -1)
            }
        }
        .compositingGroup()
        .frame(width: (22 * textScale).rounded(), height: (20 * textScale).rounded())
        .foregroundStyle(tint)
        .accessibilityHidden(true)
    }
}
