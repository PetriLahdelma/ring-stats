import Foundation

actor OuraAPI {
    private enum SnapshotPart: Sendable {
        case score(Metric, Int?)
        case heartRate(Int?)
        case stress(DailyStressRecord?)
        case resilience(DailyResilienceRecord?)
        case battery(BatteryRecord?)
        case failure(Metric?, RingStatsError)
    }

    private let auth: OAuthClient
    private let session: URLSession
    private let baseURL = URL(string: "https://api.ouraring.com/v2/usercollection/")!

    init(auth: OAuthClient, session: URLSession = NetworkSessionFactory.ephemeral()) {
        self.auth = auth
        self.session = session
    }

    func fetchSnapshot(now: Date = Date()) async throws -> HealthSnapshot {
        let token = try await auth.accessToken()
        let range = QueryDates.boundedRange(now: now)
        var readings: [Metric: MetricReading] = [:]
        var metricFailures: [Metric: RingStatsError] = [:]
        var battery: BatteryRecord?
        var firstError: RingStatsError?

        await withTaskGroup(of: SnapshotPart.self) { group in
            for metric in Metric.dailyScores {
                group.addTask { [session, baseURL] in
                    do {
                        return .score(
                            metric,
                            try await Self.fetchScore(
                                metric,
                                token: token,
                                range: range,
                                session: session,
                                baseURL: baseURL
                            )
                        )
                    } catch let error as RingStatsError {
                        return .failure(metric, error)
                    } catch {
                        return .failure(metric, .server("Oura data request failed."))
                    }
                }
            }

            group.addTask { [session, baseURL] in
                do {
                    return .heartRate(
                        try await Self.fetchHeartRate(token: token, session: session, baseURL: baseURL)
                    )
                } catch let error as RingStatsError {
                    return .failure(.heartRate, error)
                } catch {
                    return .failure(.heartRate, .server("Oura heart-rate request failed."))
                }
            }

            group.addTask { [session, baseURL] in
                do {
                    return .stress(
                        try await Self.fetchStress(
                            token: token,
                            range: range,
                            session: session,
                            baseURL: baseURL
                        )
                    )
                } catch let error as RingStatsError {
                    return .failure(.stress, error)
                } catch {
                    return .failure(.stress, .server("Oura stress request failed."))
                }
            }

            group.addTask { [session, baseURL] in
                do {
                    return .resilience(
                        try await Self.fetchResilience(
                            token: token,
                            range: range,
                            session: session,
                            baseURL: baseURL
                        )
                    )
                } catch let error as RingStatsError {
                    return .failure(.resilience, error)
                } catch {
                    return .failure(.resilience, .server("Oura resilience request failed."))
                }
            }

            group.addTask { [session, baseURL] in
                do {
                    return .battery(
                        try await Self.fetchBattery(token: token, session: session, baseURL: baseURL)
                    )
                } catch let error as RingStatsError {
                    return .failure(nil, error)
                } catch {
                    return .failure(nil, .server("Oura battery request failed."))
                }
            }

            for await part in group {
                switch part {
                case .score(let metric, let value):
                    if let value {
                        readings[metric] = MetricReading(
                            value: String(value),
                            detail: ScoreBand.label(for: value),
                            score: value
                        )
                    }
                case .heartRate(let value):
                    if let value {
                        readings[.heartRate] = MetricReading(
                            value: String(value),
                            detail: "bpm",
                            score: nil
                        )
                    }
                case .stress(let value):
                    if let value {
                        let minutes = value.stressHigh.map { max(0, ($0 + 30) / 60) }
                        readings[.stress] = MetricReading(
                            value: minutes.map { "\($0)m" } ?? "—",
                            detail: value.daySummary?.capitalized ?? "High stress",
                            score: nil
                        )
                    }
                case .resilience(let value):
                    if let level = value?.level {
                        readings[.resilience] = MetricReading(
                            value: level.capitalized,
                            detail: "Long-term",
                            score: nil
                        )
                    }
                case .battery(let value):
                    battery = value
                case .failure(let metric, let error):
                    if firstError == nil { firstError = error }
                    if let metric { metricFailures[metric] = error }
                }
            }
        }

        guard !readings.isEmpty || battery != nil else {
            throw firstError ?? RingStatsError.server("No Oura data was available. Open the Oura phone app to sync, then try again.")
        }
        for (metric, error) in metricFailures where readings[metric] == nil {
            let permissionMissing = error.localizedDescription.localizedCaseInsensitiveContains("permission")
            readings[metric] = MetricReading(
                value: "—",
                detail: permissionMissing ? "Permission required" : "Unavailable",
                score: nil
            )
        }
        return HealthSnapshot(readings: readings, battery: battery, fetchedAt: now)
    }

    private static func fetchScore(_ metric: Metric, token: String, range: (start: String, end: String), session: URLSession, baseURL: URL) async throws -> Int? {
        guard let endpoint = metric.dailyScoreEndpoint else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: range.start),
            URLQueryItem(name: "end_date", value: range.end),
            URLQueryItem(name: "fields", value: "day,score"),
        ]
        let data = try await fetch(components.url!, token: token, session: session)
        let values = try JSONDecoder().decode(ScoreEnvelope.self, from: data).data
        return values.sorted { $0.day < $1.day }.last(where: { $0.score != nil })?.score
    }

    private static func fetchHeartRate(token: String, session: URLSession, baseURL: URL) async throws -> Int? {
        var components = URLComponents(url: baseURL.appendingPathComponent("heartrate"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latest", value: "true"),
            URLQueryItem(name: "fields", value: "timestamp,bpm,source"),
        ]
        let data = try await fetch(components.url!, token: token, session: session)
        let values = try JSONDecoder().decode(HeartRateEnvelope.self, from: data).data
        return values.max { $0.timestamp < $1.timestamp }?.bpm
    }

    private static func fetchStress(token: String, range: (start: String, end: String), session: URLSession, baseURL: URL) async throws -> DailyStressRecord? {
        var components = URLComponents(url: baseURL.appendingPathComponent("daily_stress"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: range.start),
            URLQueryItem(name: "end_date", value: range.end),
            URLQueryItem(name: "fields", value: "day,day_summary,stress_high,recovery_high"),
        ]
        let data = try await fetch(components.url!, token: token, session: session)
        let values = try JSONDecoder().decode(DailyStressEnvelope.self, from: data).data
        return values.max { $0.day < $1.day }
    }

    private static func fetchResilience(token: String, range: (start: String, end: String), session: URLSession, baseURL: URL) async throws -> DailyResilienceRecord? {
        var components = URLComponents(url: baseURL.appendingPathComponent("daily_resilience"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: range.start),
            URLQueryItem(name: "end_date", value: range.end),
            URLQueryItem(name: "fields", value: "day,level"),
        ]
        let data = try await fetch(components.url!, token: token, session: session)
        let values = try JSONDecoder().decode(DailyResilienceEnvelope.self, from: data).data
        return values.max { $0.day < $1.day }
    }

    private static func fetchBattery(token: String, session: URLSession, baseURL: URL) async throws -> BatteryRecord? {
        var components = URLComponents(url: baseURL.appendingPathComponent("ring_battery_level"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "latest", value: "true")]
        let data = try await fetch(components.url!, token: token, session: session)
        return try JSONDecoder().decode(BatteryEnvelope.self, from: data).data.first
    }

    private static func fetch(_ url: URL, token: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RingStatsError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).detail) ?? ""
            if http.statusCode == 401, detail.localizedCaseInsensitiveContains("scope") {
                throw RingStatsError.server("Oura permissions are missing. Enable Daily, Heart Rate, Stress, and Ring Configuration in the developer portal, then reauthorize.")
            }
            if http.statusCode == 403 {
                throw RingStatsError.server("Oura denied API access. Confirm that your membership is active, then reconnect.")
            }
            throw RingStatsError.server(detail.isEmpty ? "Oura data request failed (HTTP \(http.statusCode))." : detail)
        }
        return data
    }
}

private struct APIErrorEnvelope: Decodable {
    let detail: String?
}
