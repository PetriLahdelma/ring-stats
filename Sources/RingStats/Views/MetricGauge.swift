import SwiftUI

struct MetricGauge: View {
    let metric: Metric
    let reading: MetricReading?
    let pending: Bool
    let theme: AppTheme

    private let scoreStrokeWidth: CGFloat = 8

    private var fraction: Double {
        Double(max(0, min(reading?.score ?? 0, 100))) / 100
    }

    private var displayValue: String { reading?.value ?? "—" }

    private var valueFontSize: CGFloat {
        metric == .resilience ? 18 : 28
    }

    private var valueBaselineOffset: CGFloat {
        theme == .landscape && metric == .resilience ? 4 : 0
    }

    private var shouldShowDetail: Bool {
        guard theme == .landscape else { return true }
        guard !pending, reading?.availability == .available else { return true }
        if reading?.observedAt != nil { return true }
        guard let sourceDay = reading?.sourceDay else { return false }
        return sourceDay != QueryDates.dayString(for: Date())
    }

    private var detailText: String {
        guard let reading else { return pending ? "Updating…" : "No data" }
        guard let observedAt = reading.observedAt else { return reading.detail ?? "No data" }
        let age = max(0, Date().timeIntervalSince(observedAt))
        let compactAge = age < 3_600
            ? "\(max(1, Int(age / 60)))m ago"
            : "\(Int(age / 3_600))h ago"
        return [reading.detail, compactAge].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if pending {
                    ScoreLoadingSpinner(theme: theme)
                        .accessibilityLabel("\(metric.title) updating")
                } else if theme == .landscape || !metric.isDailyScore {
                    VStack(spacing: 3) {
                        Image(systemName: metric.symbolName)
                            .font(.system(size: 18, weight: .regular))
                        Text(displayValue)
                            .font(.system(size: valueFontSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .offset(y: valueBaselineOffset)
                    }
                    .foregroundStyle(theme.primaryContent)
                } else {
                    if reading?.score != nil {
                        Circle()
                            .inset(by: scoreStrokeWidth / 2)
                            .trim(from: 0, to: fraction)
                            .stroke(
                                theme.score,
                                style: StrokeStyle(lineWidth: scoreStrokeWidth, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                    Text(displayValue)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.primaryContent)
                }
            }
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(metric.title)
                    .font(.system(size: 12, weight: .semibold))
                if shouldShowDetail {
                    Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryContent)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                }
            }
            .padding(.top, 12)
        }
        .frame(width: MetricStripLayout.itemWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            pending
                ? "\(metric.title) updating"
                : "\(metric.title), \(reading?.value ?? "no data"), \(reading?.detail ?? "")"
        )
    }
}

struct ScoreLoadingSpinner: View {
    let theme: AppTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.72)
            .stroke(
                theme.primaryContent.opacity(theme == .landscape ? 0.72 : 0.56),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 18, height: 18)
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
    let theme: AppTheme

    private var batteryStatus: String {
        guard let battery else { return "Battery" }
        return battery.level.map { "Battery \($0)%" } ?? "Battery —"
    }

    private var chargingStatus: String {
        guard let battery else { return loading ? "Updating…" : "Unavailable" }
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
                if let sampleAge {
                    Text(sampleAge)
                        .foregroundStyle(theme.primaryContent.opacity(0.5))
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
