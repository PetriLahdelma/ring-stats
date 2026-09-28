import Foundation
import RingStatsCore

package struct DailyScore: Codable, Sendable, Equatable {
    package let day: String
    package let score: Int?
}

package struct ScoreEnvelope: Codable, Sendable {
    package let data: [DailyScore]
}

package struct HeartRateRecord: Codable, Sendable, Equatable {
    package let timestamp: Date
    package let bpm: Int
    package let source: String

    private enum CodingKeys: String, CodingKey {
        case timestamp, bpm, source
    }

    package init(from decoder: any Decoder) throws {
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

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ISO8601DateFormatter().string(from: timestamp), forKey: .timestamp)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(source, forKey: .source)
    }
}

package struct HeartRateEnvelope: Codable, Sendable {
    package let data: [HeartRateRecord]
}

package struct DailyStressRecord: Codable, Sendable, Equatable {
    package let day: String
    package let daySummary: String?
    package let recoveryHigh: Int?
    package let stressHigh: Int?

    package enum CodingKeys: String, CodingKey {
        case day
        case daySummary = "day_summary"
        case recoveryHigh = "recovery_high"
        case stressHigh = "stress_high"
    }
}

package struct DailyStressEnvelope: Codable, Sendable {
    package let data: [DailyStressRecord]
}

package struct DailyResilienceRecord: Codable, Sendable, Equatable {
    package let day: String
    package let level: String?
}

package struct DailyResilienceEnvelope: Codable, Sendable {
    package let data: [DailyResilienceRecord]
}

package struct BatteryRecord: Codable, Sendable, Equatable {
    package let level: Int?
    package let charging: Bool?
    package let inCharger: Bool?
    package let timestamp: String?

    package enum CodingKeys: String, CodingKey {
        case level, charging, timestamp
        case inCharger = "in_charger"
    }
}

extension BatteryRecord {
    package var reading: BatteryReading {
        BatteryReading(level: level, isCharging: charging == true || inCharger == true)
    }
}

package struct BatteryEnvelope: Codable, Sendable {
    package let data: [BatteryRecord]
}

/// Oura's own score bands. Other providers band their scores differently.
package enum ScoreBand {
    package static func label(for score: Int?) -> String {
        guard let score else { return "No data" }
        return switch score {
        case 85...: "Optimal"
        case 70..<85: "Good"
        case 60..<70: "Fair"
        default: "Pay attention"
        }
    }
}

package struct OAuthToken: Codable, Sendable, Equatable {
    package let accessToken: String
    package let refreshToken: String
    package let expiresAt: Date

    package enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }

    package var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 90 }
}

package struct TokenResponse: Decodable, Sendable {
    package let accessToken: String
    package let refreshToken: String
    package let expiresIn: TimeInterval

    package enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    package func token(now: Date = Date()) -> OAuthToken {
        OAuthToken(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(expiresIn))
    }
}
