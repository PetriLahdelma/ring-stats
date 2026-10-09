import Foundation

/// A statistic Ring Stats can show. Each case keeps its vendor's meaning:
/// another provider's "recovery" is a different measure from Oura's Readiness
/// and gets its own case rather than reusing this one. Raw values are
/// persisted in `MetricConfiguration`, so they must not change.
package enum Metric: String, CaseIterable, Codable, Identifiable, Sendable {
    case readiness
    case sleep
    case activity
    case heartRate
    case stress
    case resilience

    package static let defaultVisible: [Metric] = [.readiness, .sleep, .activity, .heartRate, .stress]
    package static let dailyScores: [Metric] = [.readiness, .sleep, .activity]

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .readiness: "Readiness"
        case .sleep: "Sleep"
        case .activity: "Activity"
        case .heartRate: "Heart rate"
        case .stress: "Stress"
        case .resilience: "Resilience"
        }
    }

    package var symbolName: String {
        switch self {
        case .readiness: "leaf"
        case .sleep: "moon"
        case .activity: "flame"
        case .heartRate: "heart"
        // Follows the Oura app's convention: zigzag waves for Stress and
        // flowing wind lines for Resilience.
        case .stress: "water.waves"
        case .resilience: "wind"
        }
    }

    /// Whether the metric is a 0 to 100 daily score, drawn as a gauge.
    package var isDailyScore: Bool { Self.dailyScores.contains(self) }
}

package enum MetricAvailability: Sendable, Equatable {
    /// A value fetched during the latest refresh.
    case available
    /// A previously fetched value retained because the latest request for this
    /// metric failed transiently.
    case stale
    /// The provider denied the scope for this metric.
    case permissionRequired
    /// The request failed and no earlier value exists.
    case unavailable
    /// The request succeeded but the provider has no record for the range yet.
    case noData
}

package struct MetricReading: Sendable, Equatable {
    package let value: String
    package let detail: String?
    package let score: Int?
    package let observedAt: Date?
    package let sourceDay: String?
    package let availability: MetricAvailability
    /// For a stale reading, when it was last successfully fetched.
    package let lastFetchedAt: Date?

    package init(
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

    /// Whether the value came from the provider at some point, as opposed to a placeholder.
    package var hasValue: Bool { availability == .available || availability == .stale }

    /// - Parameter fetchedAt: When this value was fetched. A reading that is
    ///   already stale keeps its original time.
    package func markedStale(fetchedAt: Date? = nil) -> MetricReading {
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

/// A ring battery sample. Battery percentage is a quantity every provider
/// reports the same way, so it has one neutral shape.
package struct BatteryReading: Sendable, Equatable {
    package let level: Int?
    package let isCharging: Bool

    package init(level: Int?, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
}

package struct MetricConfiguration: Codable, Sendable, Equatable {
    package static let storageKey = "metric-shortcuts"
    package static let `default` = MetricConfiguration(
        order: Metric.defaultVisible + [.resilience],
        hidden: [.resilience]
    )

    package var order: [Metric]
    package var hidden: Set<Metric>

    package var visibleMetrics: [Metric] {
        order.filter { !hidden.contains($0) }
    }

    package var encoded: String {
        guard let data = try? JSONEncoder().encode(normalized),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    package var normalized: MetricConfiguration {
        var seen = Set<Metric>()
        var normalizedOrder = order.filter { seen.insert($0).inserted }
        normalizedOrder.append(contentsOf: Metric.allCases.filter { seen.insert($0).inserted })
        let normalizedHidden = hidden.intersection(Set(Metric.allCases))
        return MetricConfiguration(order: normalizedOrder, hidden: normalizedHidden)
    }

    package func moving(_ source: Metric, relativeTo target: Metric, after: Bool) -> MetricConfiguration {
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

    package func moving(fromOffsets sourceOffsets: IndexSet, toOffset destination: Int) -> MetricConfiguration {
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

    package func moving(_ metric: Metric, by offset: Int) -> MetricConfiguration {
        let current = normalized
        guard let source = current.order.firstIndex(of: metric), offset != 0 else { return current }
        let target = source + offset
        guard current.order.indices.contains(target) else { return current }
        let destination = offset > 0 ? target + 1 : target
        return current.moving(fromOffsets: IndexSet(integer: source), toOffset: destination)
    }

    package func reorderCapabilities(for metric: Metric) -> MetricReorderCapabilities? {
        let current = normalized
        guard let index = current.order.firstIndex(of: metric) else { return nil }
        return MetricReorderCapabilities(
            position: index + 1,
            total: current.order.count,
            canMoveUp: index > current.order.startIndex,
            canMoveDown: index < current.order.index(before: current.order.endIndex)
        )
    }

    package static func decode(_ rawValue: String?) -> MetricConfiguration {
        guard let rawValue,
              let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MetricConfiguration.self, from: data) else {
            return .default
        }
        let normalized = decoded.normalized
        return normalized.visibleMetrics.isEmpty ? .default : normalized
    }
}

package struct MetricReorderCapabilities: Sendable, Equatable {
    package let position: Int
    package let total: Int
    package let canMoveUp: Bool
    package let canMoveDown: Bool
}

package struct HealthSnapshot: Sendable, Equatable {
    /// How long a failed stat waits before a popover open retries it, unless
    /// the provider asked for longer with Retry-After. It keeps a persistently failing
    /// endpoint from being fetched on every open.
    package static let failureRetryInterval: TimeInterval = 60
    /// A stale value older than this is dropped rather than shown as current.
    package static let staleRetentionLimit: TimeInterval = 24 * 3_600

    package var readings: [Metric: MetricReading]
    package var battery: BatteryReading?
    package var fetchedAt: Date
    package var coveredMetrics: Set<Metric>
    /// Metrics whose latest request failed, keyed to the failure.
    package var failedMetrics: [Metric: RingStatsError]
    /// Why the latest battery request failed, if it did.
    package var batteryFailure: RingStatsError?
    package var batteryIsStale: Bool
    /// When a stale battery reading was last fetched, so it expires like a
    /// stale stat. Nil for a fresh reading, which was fetched at `fetchedAt`.
    package var batteryFetchedAt: Date?

    package init(
        readings: [Metric: MetricReading],
        battery: BatteryReading?,
        fetchedAt: Date,
        coveredMetrics: Set<Metric>? = nil,
        failedMetrics: [Metric: RingStatsError] = [:],
        batteryFailure: RingStatsError? = nil,
        batteryIsStale: Bool = false,
        batteryFetchedAt: Date? = nil
    ) {
        self.readings = readings
        self.battery = battery
        self.fetchedAt = fetchedAt
        self.coveredMetrics = coveredMetrics ?? Set(readings.keys)
        self.failedMetrics = failedMetrics
        self.batteryFailure = batteryFailure
        self.batteryIsStale = batteryIsStale
        self.batteryFetchedAt = batteryFetchedAt
    }

    package static let empty = HealthSnapshot(
        readings: [:],
        battery: nil,
        fetchedAt: .distantPast,
        coveredMetrics: []
    )

    package var hasData: Bool {
        readings.values.contains(where: \.hasValue) || battery != nil
    }

    /// Failures a later refresh may fix. Missing permission is excluded because
    /// retrying cannot succeed until the user reauthorizes.
    package var transientFailures: Set<Metric> {
        Set(failedMetrics.filter { $0.value.isRetryable }.keys)
    }

    package var batteryFailedTransiently: Bool { batteryFailure?.isRetryable == true }
    package var batteryNeedsPermission: Bool { batteryFailure == .insufficientScope }

    package var hasTransientFailures: Bool { !transientFailures.isEmpty || batteryFailedTransiently }

    package var staleMetrics: [Metric] {
        readings.filter { $0.value.availability == .stale }.map(\.key)
    }

    /// How long to wait before retrying this snapshot's transient failures:
    /// the standard interval, or longer when the provider rate limited a request.
    package var retryDelay: TimeInterval {
        let failures = Array(failedMetrics.values) + [batteryFailure].compactMap { $0 }
        let retryAfter = failures.compactMap { failure -> TimeInterval? in
            if case .rateLimited(let seconds) = failure { return seconds }
            return nil
        }.max() ?? 0
        return max(Self.failureRetryInterval, min(retryAfter, 3_600))
    }

    package func isFresh(at date: Date, ttl: TimeInterval) -> Bool {
        hasData && date.timeIntervalSince(fetchedAt) < ttl
    }

    /// Whether a popover open can reuse this snapshot. A snapshot with a
    /// transient failure among the requested stats expires after `retryDelay`
    /// instead of the full TTL.
    package func isFresh(
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
    package func merging(previous: HealthSnapshot) -> HealthSnapshot {
        var merged = self
        for metric in transientFailures {
            guard let earlier = previous.readings[metric], earlier.hasValue else { continue }
            let stale = earlier.markedStale(fetchedAt: previous.fetchedAt)
            let lastFetched = stale.lastFetchedAt ?? previous.fetchedAt
            guard fetchedAt.timeIntervalSince(lastFetched) < Self.staleRetentionLimit else { continue }
            merged.readings[metric] = stale
        }
        if batteryFailedTransiently, battery == nil, let earlierBattery = previous.battery {
            let lastFetched = previous.batteryFetchedAt ?? previous.fetchedAt
            if fetchedAt.timeIntervalSince(lastFetched) < Self.staleRetentionLimit {
                merged.battery = earlierBattery
                merged.batteryIsStale = true
                merged.batteryFetchedAt = lastFetched
            }
        }
        return merged
    }
}

package enum RefreshOutcome: Sendable, Equatable {
    case none
    case succeeded(at: Date)
    case partial(at: Date)
    case failed(at: Date)
}

package enum RefreshPolicy: Sendable, Equatable {
    case ifStale
    case force
}

package enum AppState: Sendable, Equatable {
    case unconfigured
    case configured
    case authorizing
    case connected
    case refreshing
    case authorizationExpired
    case failed(message: String, connected: Bool, configured: Bool)

    package var isConfigured: Bool {
        switch self {
        case .unconfigured: false
        case .failed(_, _, let configured): configured
        default: true
        }
    }

    package var isConnected: Bool {
        switch self {
        case .connected, .refreshing: true
        case .failed(_, let connected, _): connected
        default: false
        }
    }

    package var isLoading: Bool {
        switch self {
        case .authorizing, .refreshing: true
        default: false
        }
    }
}

package enum QueryDates {
    package static func boundedRange(now: Date = Date(), calendar: Calendar = .current) -> (start: String, end: String) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }

    package static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

package struct ClientCredentials: Codable, Sendable, Equatable {
    package let clientID: String
    package let clientSecret: String
    /// The redirect URI registered with this application. Credentials saved
    /// before Oura required `localhost` have none and keep the numeric one.
    package let redirectURI: String?

    package init(clientID: String, clientSecret: String, redirectURI: String? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
    }

    package var callbackURL: String { redirectURI ?? OAuthLoopback.legacyCallbackURL }
}

extension MetricReading {
    /// What a tile shows when a stat has no value, by why it has none.
    package static func placeholder(for failure: RingStatsError?) -> MetricReading {
        switch failure {
        case .none:
            MetricReading(value: "—", detail: "Not published", score: nil, availability: .noData)
        case .some(.insufficientScope):
            MetricReading(value: "—", detail: "Needs access", score: nil, availability: .permissionRequired)
        case .some:
            MetricReading(value: "—", detail: "Unavailable", score: nil, availability: .unavailable)
        }
    }
}

package enum RingStatsError: LocalizedError, Sendable, Equatable {
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
    package var isRetryable: Bool {
        switch self {
        case .insufficientScope, .authenticationRequired, .notConfigured, .notConnected,
             .invalidClientCredentials, .authorizationRestartRequired, .invalidRequestedScope:
            false
        default:
            true
        }
    }

    /// The name used when no provider is known, such as through
    /// `localizedDescription`. The app passes the provider's display name.
    package static let unknownProviderName = "the service"

    package var errorDescription: String? { message(provider: Self.unknownProviderName) }

    /// The user-facing message, naming the provider that failed. Templates
    /// read correctly with a brand name ("Oura") and with the generic
    /// fallback ("the service"); the first letter is capitalized either way.
    package func message(provider: String) -> String {
        let text: String = switch self {
        case .notConfigured: "Enter the application credentials for \(provider) first."
        case .notConnected: "Connect \(provider) first."
        case .invalidResponse: "\(provider) returned an invalid response."
        case .authenticationRequired: "The authorization with \(provider) has expired. Reauthorize to continue."
        case .invalidClientCredentials: "\(provider) rejected the Client ID or Client Secret. Check the developer application credentials and try again."
        case .authorizationRestartRequired: "\(provider) rejected the authorization code. Start the browser connection again."
        case .invalidRequestedScope: "\(provider) rejected a requested permission. Check the developer application scopes and reconnect."
        case .insufficientScope: "Permission from \(provider) is missing for this statistic. Reauthorize with the requested permission."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter.isFinite {
                "\(provider) is temporarily rate limiting requests. Try again in \(Int(ceil(min(retryAfter, 3_600)))) seconds."
            } else {
                "\(provider) is temporarily rate limiting requests. Try again shortly."
            }
        case .timedOut: "The request to \(provider) timed out. Check your connection and try again."
        case .malformedData: "\(provider) returned data in an unexpected format."
        case .credentialStore(let message): message
        case .transport(let message): message
        case .server(let message): message
        case .callback(let message): message
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
