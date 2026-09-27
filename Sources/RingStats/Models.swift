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
    let timestamp: Date
    let bpm: Int
    let source: String

    private enum CodingKeys: String, CodingKey {
        case timestamp, bpm, source
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawTimestamp = try container.decode(String.self, forKey: .timestamp)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        guard let timestamp = fractional.date(from: rawTimestamp) ?? standard.date(from: rawTimestamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp."
            )
        }
        self.timestamp = timestamp
        self.bpm = try container.decode(Int.self, forKey: .bpm)
        self.source = try container.decode(String.self, forKey: .source)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ISO8601DateFormatter().string(from: timestamp), forKey: .timestamp)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(source, forKey: .source)
    }
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

    var requiredScope: OuraScope {
        switch self {
        case .readiness, .sleep, .activity, .resilience: .daily
        case .heartRate: .heartRate
        case .stress: .stress
        }
    }
}

enum OuraScope: String, CaseIterable, Sendable {
    case daily
    case heartRate = "heartrate"
    case stress
    case ringConfiguration = "ring_configuration"

    static func required(for metrics: Set<Metric>) -> Set<OuraScope> {
        Set(metrics.map(\.requiredScope)).union([.ringConfiguration])
    }
}

enum MetricAvailability: Sendable, Equatable {
    /// A value fetched during the latest refresh.
    case available
    /// A previously fetched value retained because the latest request for this
    /// metric failed transiently.
    case stale
    /// Oura denied the scope for this metric.
    case permissionRequired
    /// The request failed and no earlier value exists.
    case unavailable
    /// The request succeeded but Oura has no record for the range yet.
    case noData
}

struct MetricReading: Sendable, Equatable {
    let value: String
    let detail: String?
    let score: Int?
    let observedAt: Date?
    let sourceDay: String?
    let availability: MetricAvailability
    /// For a stale reading, when it was last successfully fetched.
    let lastFetchedAt: Date?

    init(
        value: String,
        detail: String?,
        score: Int?,
        observedAt: Date? = nil,
        sourceDay: String? = nil,
        availability: MetricAvailability = .available,
        lastFetchedAt: Date? = nil
    ) {
        self.value = value
        self.detail = detail
        self.score = score
        self.observedAt = observedAt
        self.sourceDay = sourceDay
        self.availability = availability
        self.lastFetchedAt = lastFetchedAt
    }

    /// Whether the value came from Oura at some point, as opposed to a placeholder.
    var hasValue: Bool { availability == .available || availability == .stale }

    /// - Parameter fetchedAt: When this value was fetched. A reading that is
    ///   already stale keeps its original time.
    func markedStale(fetchedAt: Date? = nil) -> MetricReading {
        MetricReading(
            value: value,
            detail: detail,
            score: score,
            observedAt: observedAt,
            sourceDay: sourceDay,
            availability: .stale,
            lastFetchedAt: availability == .stale ? lastFetchedAt : (fetchedAt ?? lastFetchedAt)
        )
    }
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

    func moving(fromOffsets sourceOffsets: IndexSet, toOffset destination: Int) -> MetricConfiguration {
        let current = normalized
        guard !sourceOffsets.isEmpty,
              sourceOffsets.allSatisfy(current.order.indices.contains),
              (0...current.order.count).contains(destination) else { return current }

        let moved = sourceOffsets.sorted().map { current.order[$0] }
        var remaining = current.order.enumerated()
            .filter { !sourceOffsets.contains($0.offset) }
            .map(\.element)
        let removedBeforeDestination = sourceOffsets.filter { $0 < destination }.count
        let insertionIndex = max(0, min(remaining.count, destination - removedBeforeDestination))
        remaining.insert(contentsOf: moved, at: insertionIndex)
        return MetricConfiguration(order: remaining, hidden: current.hidden).normalized
    }

    func moving(_ metric: Metric, by offset: Int) -> MetricConfiguration {
        let current = normalized
        guard let source = current.order.firstIndex(of: metric), offset != 0 else { return current }
        let target = source + offset
        guard current.order.indices.contains(target) else { return current }
        let destination = offset > 0 ? target + 1 : target
        return current.moving(fromOffsets: IndexSet(integer: source), toOffset: destination)
    }

    func reorderCapabilities(for metric: Metric) -> MetricReorderCapabilities? {
        let current = normalized
        guard let index = current.order.firstIndex(of: metric) else { return nil }
        return MetricReorderCapabilities(
            position: index + 1,
            total: current.order.count,
            canMoveUp: index > current.order.startIndex,
            canMoveDown: index < current.order.index(before: current.order.endIndex)
        )
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

struct MetricReorderCapabilities: Sendable, Equatable {
    let position: Int
    let total: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
}

struct HealthSnapshot: Sendable, Equatable {
    /// How long a failed stat waits before a popover open retries it, unless
    /// Oura asked for longer with Retry-After. It keeps a persistently failing
    /// endpoint from being fetched on every open.
    static let failureRetryInterval: TimeInterval = 60
    /// A stale value older than this is dropped rather than shown as current.
    static let staleRetentionLimit: TimeInterval = 24 * 3_600

    var readings: [Metric: MetricReading]
    var battery: BatteryRecord?
    var fetchedAt: Date
    var coveredMetrics: Set<Metric>
    /// Metrics whose latest request failed, keyed to the failure.
    var failedMetrics: [Metric: RingStatsError]
    /// Why the latest battery request failed, if it did.
    var batteryFailure: RingStatsError?
    var batteryIsStale: Bool

    init(
        readings: [Metric: MetricReading],
        battery: BatteryRecord?,
        fetchedAt: Date,
        coveredMetrics: Set<Metric>? = nil,
        failedMetrics: [Metric: RingStatsError] = [:],
        batteryFailure: RingStatsError? = nil,
        batteryIsStale: Bool = false
    ) {
        self.readings = readings
        self.battery = battery
        self.fetchedAt = fetchedAt
        self.coveredMetrics = coveredMetrics ?? Set(readings.keys)
        self.failedMetrics = failedMetrics
        self.batteryFailure = batteryFailure
        self.batteryIsStale = batteryIsStale
    }

    static let empty = HealthSnapshot(
        readings: [:],
        battery: nil,
        fetchedAt: .distantPast,
        coveredMetrics: []
    )

    var hasData: Bool {
        readings.values.contains(where: \.hasValue) || battery != nil
    }

    /// Failures a later refresh may fix. Missing permission is excluded because
    /// retrying cannot succeed until the user reauthorizes.
    var transientFailures: Set<Metric> {
        Set(failedMetrics.filter { $0.value.isRetryable }.keys)
    }

    var batteryFailedTransiently: Bool { batteryFailure?.isRetryable == true }
    var batteryNeedsPermission: Bool { batteryFailure == .insufficientScope }

    var hasTransientFailures: Bool { !transientFailures.isEmpty || batteryFailedTransiently }

    var staleMetrics: [Metric] {
        readings.filter { $0.value.availability == .stale }.map(\.key)
    }

    /// How long to wait before retrying this snapshot's transient failures:
    /// the standard interval, or longer when Oura rate limited a request.
    var retryDelay: TimeInterval {
        let failures = Array(failedMetrics.values) + [batteryFailure].compactMap { $0 }
        let retryAfter = failures.compactMap { failure -> TimeInterval? in
            if case .rateLimited(let seconds) = failure { return seconds }
            return nil
        }.max() ?? 0
        return max(Self.failureRetryInterval, retryAfter)
    }

    func isFresh(at date: Date, ttl: TimeInterval) -> Bool {
        hasData && date.timeIntervalSince(fetchedAt) < ttl
    }

    /// Whether a popover open can reuse this snapshot. A snapshot with a
    /// transient failure among the requested stats expires after `retryDelay`
    /// instead of the full TTL.
    func isFresh(
        for metrics: Set<Metric>,
        at date: Date,
        ttl: TimeInterval
    ) -> Bool {
        guard hasData, coveredMetrics.isSuperset(of: metrics) else { return false }
        let age = date.timeIntervalSince(fetchedAt)
        let failedRequested = !transientFailures.isDisjoint(with: metrics) || batteryFailedTransiently
        return age < (failedRequested ? min(ttl, retryDelay) : ttl)
    }

    /// Combines a new refresh with the previous snapshot. A metric that failed
    /// transiently keeps its last known value, marked stale, instead of being
    /// replaced by a placeholder, until it is older than
    /// `staleRetentionLimit`. Permission failures and genuine absence are
    /// reported as they are, because an old value would misrepresent them.
    func merging(previous: HealthSnapshot) -> HealthSnapshot {
        var merged = self
        for metric in transientFailures {
            guard let earlier = previous.readings[metric], earlier.hasValue else { continue }
            let stale = earlier.markedStale(fetchedAt: previous.fetchedAt)
            let lastFetched = stale.lastFetchedAt ?? previous.fetchedAt
            guard fetchedAt.timeIntervalSince(lastFetched) < Self.staleRetentionLimit else { continue }
            merged.readings[metric] = stale
        }
        if batteryFailedTransiently, battery == nil, let earlierBattery = previous.battery {
            merged.battery = earlierBattery
            merged.batteryIsStale = true
        }
        return merged
    }
}

enum RefreshOutcome: Sendable, Equatable {
    case none
    case succeeded(at: Date)
    case partial(at: Date)
    case failed(at: Date)
}

enum RefreshPolicy: Sendable, Equatable {
    case ifStale
    case force
}

enum AppState: Sendable, Equatable {
    case unconfigured
    case configured
    case authorizing
    case connected
    case refreshing
    case authorizationExpired
    case failed(message: String, connected: Bool, configured: Bool)

    var isConfigured: Bool {
        switch self {
        case .unconfigured: false
        case .failed(_, _, let configured): configured
        default: true
        }
    }

    var isConnected: Bool {
        switch self {
        case .connected, .refreshing: true
        case .failed(_, let connected, _): connected
        default: false
        }
    }

    var isLoading: Bool {
        switch self {
        case .authorizing, .refreshing: true
        default: false
        }
    }
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

    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

enum RingStatsError: LocalizedError, Sendable, Equatable {
    case notConfigured
    case notConnected
    case invalidResponse
    case authenticationRequired
    case invalidClientCredentials
    case authorizationRestartRequired
    case invalidRequestedScope
    case insufficientScope
    case rateLimited(retryAfter: TimeInterval?)
    case timedOut
    case malformedData
    case credentialStore(String)
    case transport(String)
    case server(String)
    case callback(String)

    /// Whether retrying the same request later could succeed. Missing
    /// permission and expired authorization need the user to act first.
    var isRetryable: Bool {
        switch self {
        case .insufficientScope, .authenticationRequired, .notConfigured, .notConnected,
             .invalidClientCredentials, .authorizationRestartRequired, .invalidRequestedScope:
            false
        default:
            true
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Enter Oura application credentials first."
        case .notConnected: "Connect your Oura account first."
        case .invalidResponse: "Oura returned an invalid response."
        case .authenticationRequired: "Your Oura authorization has expired. Reauthorize to continue."
        case .invalidClientCredentials: "Oura rejected the Client ID or Client Secret. Check the developer application credentials and try again."
        case .authorizationRestartRequired: "Oura rejected the authorization code. Start the browser connection again."
        case .invalidRequestedScope: "Oura rejected a requested permission. Check the developer application scopes and reconnect."
        case .insufficientScope: "Oura permission is missing for this statistic. Reauthorize with the requested permission."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Oura is temporarily rate limiting requests. Try again in \(Int(ceil(retryAfter))) seconds."
            } else {
                "Oura is temporarily rate limiting requests. Try again shortly."
            }
        case .timedOut: "The Oura request timed out. Check your connection and try again."
        case .malformedData: "Oura returned data in an unexpected format."
        case .credentialStore(let message): message
        case .transport(let message): message
        case .server(let message): message
        case .callback(let message): message
        }
    }
}
