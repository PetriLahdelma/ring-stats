import Foundation

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case ringStats = "ring-stats"
    case landscape

    static let storageKey = "selected-theme"

    static func resolve(_ storedValue: String) -> AppTheme {
        if storedValue == "oura-original" { return .landscape }
        return AppTheme(rawValue: storedValue) ?? .ringStats
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ringStats: "Ring Stats"
        case .landscape: "Landscape"
        }
    }

    var summary: String {
        switch self {
        case .ringStats:
            "Warm canvas with signal-blue gauges and dark text."
        case .landscape:
            "Full-width landscape with white icons, numbers, and labels."
        }
    }
}

struct DailyScore: Codable, Sendable, Equatable {
    let day: String
    let score: Int?
}

struct ScoreEnvelope: Codable, Sendable {
    let data: [DailyScore]
}

struct HeartRateRecord: Codable, Sendable, Equatable {
    let timestamp: String
    let bpm: Int
    let source: String
}

struct HeartRateEnvelope: Codable, Sendable {
    let data: [HeartRateRecord]
}

struct DailyStressRecord: Codable, Sendable, Equatable {
    let day: String
    let daySummary: String?
    let recoveryHigh: Int?
    let stressHigh: Int?

    enum CodingKeys: String, CodingKey {
        case day
        case daySummary = "day_summary"
        case recoveryHigh = "recovery_high"
        case stressHigh = "stress_high"
    }
}

struct DailyStressEnvelope: Codable, Sendable {
    let data: [DailyStressRecord]
}

struct DailyResilienceRecord: Codable, Sendable, Equatable {
    let day: String
    let level: String?
}

struct DailyResilienceEnvelope: Codable, Sendable {
    let data: [DailyResilienceRecord]
}

struct BatteryRecord: Codable, Sendable, Equatable {
    let level: Int?
    let charging: Bool?
    let inCharger: Bool?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case level, charging, timestamp
        case inCharger = "in_charger"
    }
}

struct BatteryEnvelope: Codable, Sendable {
    let data: [BatteryRecord]
}

enum Metric: String, CaseIterable, Codable, Identifiable, Sendable {
    case readiness
    case sleep
    case activity
    case heartRate
    case stress
    case resilience

    static let defaultVisible: [Metric] = [.readiness, .sleep, .activity, .heartRate, .stress]
    static let dailyScores: [Metric] = [.readiness, .sleep, .activity]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readiness: "Readiness"
        case .sleep: "Sleep"
        case .activity: "Activity"
        case .heartRate: "Heart rate"
        case .stress: "Stress"
        case .resilience: "Resilience"
        }
    }

    var symbolName: String {
        switch self {
        case .readiness: "leaf"
        case .sleep: "moon"
        case .activity: "flame"
        case .heartRate: "heart"
        case .stress: "waveform.path.ecg"
        case .resilience: "water.waves"
        }
    }

    var dailyScoreEndpoint: String? {
        switch self {
        case .readiness: "daily_readiness"
        case .sleep: "daily_sleep"
        case .activity: "daily_activity"
        case .heartRate, .stress, .resilience: nil
        }
    }

    var isDailyScore: Bool { dailyScoreEndpoint != nil }
}

struct MetricReading: Sendable, Equatable {
    let value: String
    let detail: String?
    let score: Int?
}

struct MetricConfiguration: Codable, Sendable, Equatable {
    static let storageKey = "metric-shortcuts"
    static let `default` = MetricConfiguration(
        order: Metric.defaultVisible + [.resilience],
        hidden: [.resilience]
    )

    var order: [Metric]
    var hidden: Set<Metric>

    var visibleMetrics: [Metric] {
        order.filter { !hidden.contains($0) }
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(normalized),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    var normalized: MetricConfiguration {
        var seen = Set<Metric>()
        var normalizedOrder = order.filter { seen.insert($0).inserted }
        normalizedOrder.append(contentsOf: Metric.allCases.filter { seen.insert($0).inserted })
        let normalizedHidden = hidden.intersection(Set(Metric.allCases))
        return MetricConfiguration(order: normalizedOrder, hidden: normalizedHidden)
    }

    func moving(_ source: Metric, relativeTo target: Metric, after: Bool) -> MetricConfiguration {
        guard source != target,
              order.contains(source),
              order.contains(target) else { return normalized }

        var updated = normalized
        updated.order.removeAll { $0 == source }
        guard let targetIndex = updated.order.firstIndex(of: target) else { return normalized }
        let insertionIndex = min(updated.order.endIndex, targetIndex + (after ? 1 : 0))
        updated.order.insert(source, at: insertionIndex)
        return updated.normalized
    }

    static func decode(_ rawValue: String?) -> MetricConfiguration {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MetricConfiguration.self, from: data) else {
            return .default
        }
        let normalized = decoded.normalized
        return normalized.visibleMetrics.isEmpty ? .default : normalized
    }
}

struct HealthSnapshot: Sendable, Equatable {
    var readings: [Metric: MetricReading]
    var battery: BatteryRecord?
    var fetchedAt: Date

    static let empty = HealthSnapshot(readings: [:], battery: nil, fetchedAt: .distantPast)
}

enum ScoreBand {
    static func label(for score: Int?) -> String {
        guard let score else { return "No data" }
        return switch score {
        case 85...: "Optimal"
        case 70..<85: "Good"
        case 60..<70: "Fair"
        default: "Pay attention"
        }
    }
}

enum QueryDates {
    static func boundedRange(now: Date = Date(), calendar: Calendar = .current) -> (start: String, end: String) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }
}

struct OAuthToken: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }

    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 90 }
}

struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    func token(now: Date = Date()) -> OAuthToken {
        OAuthToken(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(expiresIn))
    }
}

struct ClientCredentials: Codable, Sendable, Equatable {
    let clientID: String
    let clientSecret: String
}

enum RingStatsError: LocalizedError, Sendable {
    case notConfigured
    case notConnected
    case invalidResponse
    case server(String)
    case callback(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Enter Oura application credentials first."
        case .notConnected: "Connect your Oura account first."
        case .invalidResponse: "Oura returned an invalid response."
        case .server(let message): message
        case .callback(let message): message
        }
    }
}
