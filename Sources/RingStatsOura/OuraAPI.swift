import Foundation
import RingStatsCore

package actor OuraAPI: SnapshotFetching {
    private enum SnapshotPart: Sendable {
        case score(Metric, DailyScore?)
        case heartRate(HeartRateRecord?)
        case stress(DailyStressRecord?)
        case resilience(DailyResilienceRecord?)
        case battery(BatteryRecord?)
        case failure(Metric?, RingStatsError)
        case cancelled
    }

    private let auth: any AccessTokenProviding
    private let session: URLSession
    private let baseURL: URL

    package init(
        auth: any AccessTokenProviding,
        session: URLSession = NetworkSessionFactory.ephemeral(),
        baseURL: URL = URL(string: "https://api.ouraring.com/v2/usercollection/")!
    ) {
        self.auth = auth
        self.session = session
        self.baseURL = baseURL
    }

    package func fetchSnapshot(
        metrics: Set<Metric> = Set(Metric.defaultVisible),
        now: Date = Date()
    ) async throws -> HealthSnapshot {
        let token = try await auth.accessToken(forceRefresh: false)
        do {
            return try await collectSnapshot(metrics: metrics, token: token, now: now)
        } catch RingStatsError.authenticationRequired {
            let refreshedToken = try await auth.accessToken(forceRefresh: true)
            do {
                return try await collectSnapshot(metrics: metrics, token: refreshedToken, now: now)
            } catch RingStatsError.authenticationRequired {
                try await auth.invalidateAuthorization()
                throw RingStatsError.authenticationRequired
            }
        }
    }

    private func collectSnapshot(
        metrics: Set<Metric>,
        token: String,
        now: Date
    ) async throws -> HealthSnapshot {
        let range = QueryDates.boundedRange(now: now)
        var readings: [Metric: MetricReading] = [:]
        var metricFailures: [Metric: RingStatsError] = [:]
        var battery: BatteryRecord?
        var batteryFailure: RingStatsError?
        var failures: [RingStatsError] = []
        var wasCancelled = false

        await withTaskGroup(of: SnapshotPart.self) { group in
            for metric in metrics {
                group.addTask { [session, baseURL] in
                    do {
                        return try await Self.fetchPart(
                            metric,
                            token: token,
                            range: range,
                            session: session,
                            baseURL: baseURL
                        )
                    } catch is CancellationError {
                        return .cancelled
                    } catch let error as RingStatsError {
                        return .failure(metric, error)
                    } catch {
                        return .failure(metric, .transport("Oura data request failed."))
                    }
                }
            }

            group.addTask { [session, baseURL] in
                do {
                    return .battery(
                        try await Self.fetchBattery(token: token, session: session, baseURL: baseURL)
                    )
                } catch is CancellationError {
                    return .cancelled
                } catch let error as RingStatsError {
                    return .failure(nil, error)
                } catch {
                    return .failure(nil, .transport("Oura battery request failed."))
                }
            }

            for await part in group {
                switch part {
                case .score(let metric, let record):
                    if let record, let value = record.score {
                        let baseDetail = ScoreBand.label(for: value)
                        readings[metric] = MetricReading(
                            value: String(value),
                            detail: baseDetail,
                            score: value,
                            sourceDay: record.day
                        )
                    }
                case .heartRate(let record):
                    if let record {
                        readings[.heartRate] = MetricReading(
                            value: String(record.bpm),
                            detail: "bpm",
                            score: nil,
                            observedAt: record.timestamp
                        )
                    }
                case .stress(let value):
                    if let value {
                        let minutes = value.stressHigh.map { max(0, ($0 + 30) / 60) }
                        readings[.stress] = MetricReading(
                            value: minutes.map { "\($0)m" } ?? "—",
                            detail: value.daySummary?.capitalized ?? "High stress",
                            score: nil,
                            sourceDay: value.day
                        )
                    }
                case .resilience(let value):
                    if let value, let level = value.level {
                        readings[.resilience] = MetricReading(
                            value: level.capitalized,
                            detail: "Long-term",
                            score: nil,
                            sourceDay: value.day
                        )
                    }
                case .battery(let value):
                    battery = value
                case .failure(let metric, let error):
                    failures.append(error)
                    if let metric {
                        metricFailures[metric] = error
                    } else {
                        batteryFailure = error
                    }
                case .cancelled:
                    wasCancelled = true
                }
            }
        }

        if wasCancelled { throw CancellationError() }

        if failures.contains(.authenticationRequired) {
            throw RingStatsError.authenticationRequired
        }

        guard !readings.isEmpty || battery != nil else {
            throw Self.preferredError(from: failures)
                ?? RingStatsError.server("No Oura data was available. Open the Oura phone app to sync, then try again.")
        }

        for metric in metrics where readings[metric] == nil {
            readings[metric] = Self.placeholder(for: metricFailures[metric])
        }
        return HealthSnapshot(
            readings: readings,
            battery: battery?.reading,
            fetchedAt: now,
            coveredMetrics: metrics,
            failedMetrics: metricFailures.filter { metrics.contains($0.key) },
            batteryFailure: batteryFailure
        )
    }

    /// The reading shown when a metric has no value from this refresh. The view
    /// model replaces transient-failure placeholders with the last known value.
    /// Forwards to the provider-neutral placeholder in Core.
    package static func placeholder(for failure: RingStatsError?) -> MetricReading {
        MetricReading.placeholder(for: failure)
    }

    private static func fetchPart(
        _ metric: Metric,
        token: String,
        range: (start: String, end: String),
        session: URLSession,
        baseURL: URL
    ) async throws -> SnapshotPart {
        if metric.isDailyScore {
            return .score(
                metric,
                try await fetchScore(metric, token: token, range: range, session: session, baseURL: baseURL)
            )
        }
        switch metric {
        case .heartRate:
            return .heartRate(try await fetchHeartRate(token: token, session: session, baseURL: baseURL))
        case .stress:
            return .stress(try await fetchStress(token: token, range: range, session: session, baseURL: baseURL))
        case .resilience:
            return .resilience(
                try await fetchResilience(token: token, range: range, session: session, baseURL: baseURL)
            )
        case .readiness, .sleep, .activity:
            return .score(metric, nil)
        }
    }

    private static func preferredError(from errors: [RingStatsError]) -> RingStatsError? {
        errors.first(where: { if case .rateLimited = $0 { true } else { false } })
            ?? errors.first(where: { $0 == .insufficientScope })
            ?? errors.first(where: { $0 == .timedOut })
            ?? errors.first
    }


    private static func fetchScore(
        _ metric: Metric,
        token: String,
        range: (start: String, end: String),
        session: URLSession,
        baseURL: URL
    ) async throws -> DailyScore? {
        guard let endpoint = metric.dailyScoreEndpoint else { return nil }
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = dateQuery(range: range, fields: "day,score")
        let data = try await fetch(components.url!, token: token, session: session)
        do {
            let values = try JSONDecoder().decode(ScoreEnvelope.self, from: data).data
            return values.sorted { $0.day < $1.day }.last(where: { $0.score != nil })
        } catch {
            throw RingStatsError.malformedData
        }
    }

    private static func fetchHeartRate(
        token: String,
        session: URLSession,
        baseURL: URL
    ) async throws -> HeartRateRecord? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("heartrate"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "latest", value: "true"),
            URLQueryItem(name: "fields", value: "timestamp,bpm,source"),
        ]
        let data = try await fetch(components.url!, token: token, session: session)
        do {
            let values = try JSONDecoder().decode(HeartRateEnvelope.self, from: data).data
            return values.max { $0.timestamp < $1.timestamp }
        } catch {
            throw RingStatsError.malformedData
        }
    }

    private static func fetchStress(
        token: String,
        range: (start: String, end: String),
        session: URLSession,
        baseURL: URL
    ) async throws -> DailyStressRecord? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("daily_stress"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = dateQuery(
            range: range,
            fields: "day,day_summary,stress_high,recovery_high"
        )
        let data = try await fetch(components.url!, token: token, session: session)
        do {
            return try JSONDecoder().decode(DailyStressEnvelope.self, from: data).data
                .filter { $0.stressHigh != nil || $0.daySummary != nil }
                .max { $0.day < $1.day }
        } catch {
            throw RingStatsError.malformedData
        }
    }

    private static func fetchResilience(
        token: String,
        range: (start: String, end: String),
        session: URLSession,
        baseURL: URL
    ) async throws -> DailyResilienceRecord? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("daily_resilience"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = dateQuery(range: range, fields: "day,level")
        let data = try await fetch(components.url!, token: token, session: session)
        do {
            return try JSONDecoder().decode(DailyResilienceEnvelope.self, from: data).data
                .filter { $0.level != nil }
                .max { $0.day < $1.day }
        } catch {
            throw RingStatsError.malformedData
        }
    }

    private static func fetchBattery(
        token: String,
        session: URLSession,
        baseURL: URL
    ) async throws -> BatteryRecord? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("ring_battery_level"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "latest", value: "true")]
        let data = try await fetch(components.url!, token: token, session: session)
        do {
            let values = try JSONDecoder().decode(BatteryEnvelope.self, from: data).data
            return values.max { lhs, rhs in
                Self.parsedTimestamp(lhs.timestamp) < Self.parsedTimestamp(rhs.timestamp)
            }
        } catch {
            throw RingStatsError.malformedData
        }
    }

    /// The seconds to wait from a Retry-After header, or nil when the header
    /// is absent, not a whole number of seconds, or outside one second to an
    /// hour. Parsing it as a Double accepted "inf" and "1e400", which crashed
    /// the message formatter and could suppress refreshes for years.
    static func retryAfter(_ header: String?) -> TimeInterval? {
        guard let header, let seconds = Int(header.trimmingCharacters(in: .whitespaces)),
              (1...3_600).contains(seconds)
        else { return nil }
        return TimeInterval(seconds)
    }

    private static func dateQuery(
        range: (start: String, end: String),
        fields: String
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start_date", value: range.start),
            URLQueryItem(name: "end_date", value: range.end),
            URLQueryItem(name: "fields", value: fields),
        ]
    }

    private static func parsedTimestamp(_ value: String?) -> Date {
        guard let value else { return .distantPast }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
    }

    private static func fetch(_ url: URL, token: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let endpoint = OuraEndpoint(path: url.path)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            DiagnosticsLog.shared.record(.endpointUnreachable(endpoint: endpoint.diagnostic, error: .timedOut))
            throw RingStatsError.timedOut
        } catch {
            if Task.isCancelled { throw CancellationError() }
            let failure = RingStatsError.transport("Could not reach Oura. Check your internet connection and try again.")
            DiagnosticsLog.shared.record(.endpointUnreachable(endpoint: endpoint.diagnostic, error: failure))
            throw failure
        }
        guard let http = response as? HTTPURLResponse else {
            throw RingStatsError.invalidResponse
        }
        DiagnosticsLog.shared.record(.endpointResponse(endpoint: endpoint.diagnostic, status: http.statusCode))
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401:
                throw RingStatsError.authenticationRequired
            case 403:
                throw RingStatsError.insufficientScope
            case 429:
                throw RingStatsError.rateLimited(
                    retryAfter: Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"))
                )
            case 408, 504:
                throw RingStatsError.timedOut
            default:
                // Do not surface arbitrary upstream bodies in the UI. They can
                // contain HTML, internal diagnostics, or echoed request data.
                throw RingStatsError.server("Oura data request failed (HTTP \(http.statusCode)).")
            }
        }
        return data
    }
}
