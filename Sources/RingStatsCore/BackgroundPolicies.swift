import Foundation

/// When a scheduled background refresh may fetch. It keeps the popover fresh
/// without drawing power the user needs elsewhere.
package enum BackgroundRefreshPolicy {
    /// How often the scheduler wakes the app.
    package static let interval: TimeInterval = 30 * 60
    /// The minimum age of the data before a refresh on battery power or in Low
    /// Power Mode.
    package static let constrainedInterval: TimeInterval = 2 * 3_600

    /// - Parameters:
    ///   - lastFetchedAt: When the current data was fetched, or nil if none.
    ///   - constrained: Whether the Mac is on battery power or in Low Power Mode.
    package static func shouldRefresh(lastFetchedAt: Date?, now: Date, constrained: Bool) -> Bool {
        guard constrained, let lastFetchedAt else { return true }
        // The scheduler fires within a tolerance, so allow a little early.
        return now.timeIntervalSince(lastFetchedAt) >= constrainedInterval * 0.9
    }
}

/// Decides when to announce a low ring battery: once when the level drops
/// below the threshold, and not again until the ring has been charging. An old
/// reading kept from an earlier refresh never triggers it.
package struct LowBatteryAlert: Sendable, Equatable {
    /// The default level, at which the battery icon also turns to Alert.
    package static let threshold = 20
    /// The levels a user may choose.
    package static let thresholds = [10, 15, 20, 25, 30]
    /// How far above the threshold a reading must be to count as recharged.
    package static let rearmMargin = 30

    package let threshold: Int
    package private(set) var isArmed = true

    package init(threshold: Int = LowBatteryAlert.threshold) {
        self.threshold = Self.thresholds.contains(threshold) ? threshold : Self.threshold
    }

    /// Returns the level to announce, or nil when nothing should be announced.
    package mutating func evaluate(_ battery: BatteryReading?, isStale: Bool) -> Int? {
        guard let battery, !isStale, let level = battery.level else { return nil }
        // The app samples every half hour, so a full charge between samples
        // arrives as "100%, not charging"; a clearly recovered level re-arms
        // too, or one missed charging sample would silence every later drain.
        if battery.isCharging || level >= threshold + Self.rearmMargin {
            isArmed = true
            return nil
        }
        guard level < threshold, isArmed else { return nil }
        isArmed = false
        return level
    }
}

/// Hours during which no notification is shown. A span may wrap midnight;
/// "22 to 7" covers 22:00 through 06:59.
package struct QuietHours: Sendable, Equatable {
    package static let `default` = QuietHours(start: 22, end: 7)

    package var start: Int
    package var end: Int

    package init(start: Int, end: Int) {
        self.start = min(23, max(0, start))
        self.end = min(23, max(0, end))
    }

    package func contains(hour: Int) -> Bool {
        if start == end { return false }
        return start < end ? (start..<end).contains(hour) : hour >= start || hour < end
    }

    package func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        contains(hour: calendar.component(.hour, from: date))
    }
}

/// Decides when to suggest charging before bed: in the hours before quiet
/// hours begin, when the ring is draining fast enough that it would be below
/// the low-battery threshold by the time quiet hours end. The drain rate
/// comes from the levels seen over the day, in memory only; a charge resets
/// it. Once per day at most.
package struct BedtimeNudge: Sendable, Equatable {
    package struct Sample: Sendable, Equatable {
        package let level: Int
        package let at: Date
    }

    /// How long before quiet hours the suggestion may appear.
    package static let window: TimeInterval = 4 * 3_600
    /// The least history the rate is trusted on.
    package static let minimumSpan: TimeInterval = 2 * 3_600
    /// Samples older than this no longer describe today's drain.
    package static let sampleRetention: TimeInterval = 12 * 3_600

    package private(set) var samples: [Sample] = []
    package private(set) var nudgedDay: String?

    package init() {}

    /// The projected level at the end of quiet hours when a nudge is due, or nil.
    package mutating func evaluate(
        _ battery: BatteryReading?,
        isStale: Bool,
        now: Date,
        quietHours: QuietHours,
        threshold: Int,
        calendar: Calendar = .current
    ) -> Int? {
        guard let battery, !isStale, let level = battery.level else { return nil }
        if battery.isCharging {
            samples.removeAll()
            return nil
        }
        samples.removeAll { now.timeIntervalSince($0.at) > Self.sampleRetention }
        samples.append(Sample(level: level, at: now))
        guard let first = samples.first else { return nil }
        let span = now.timeIntervalSince(first.at)
        guard span >= Self.minimumSpan, first.level > level else { return nil }
        let drainPerHour = Double(first.level - level) / (span / 3_600)
        guard let bedtime = Self.next(hour: quietHours.start, after: now.addingTimeInterval(-Self.window), calendar: calendar),
              bedtime > now, bedtime.timeIntervalSince(now) <= Self.window,
              let wake = Self.next(hour: quietHours.end, after: bedtime, calendar: calendar)
        else { return nil }
        let projected = Int((Double(level) - drainPerHour * wake.timeIntervalSince(now) / 3_600).rounded())
        guard projected < threshold else { return nil }
        let today = QueryDates.dayString(for: now, calendar: calendar)
        guard nudgedDay != today else { return nil }
        nudgedDay = today
        return max(0, projected)
    }

    private static func next(hour: Int, after date: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0), matchingPolicy: .nextTime)
    }
}

/// Decides when to say that today's scores have arrived: the first refresh
/// of the day that carries a daily score for today, after one that did not.
/// Launching with the scores already there says nothing; so does a second
/// score arriving later in the day.
package struct ScoresArrival: Sendable, Equatable {
    package static let dailyScores: Set<Metric> = [.readiness, .sleep, .activity]

    package private(set) var missingDay: String?
    package private(set) var announcedDay: String?

    package init() {}

    package mutating func evaluate(_ snapshot: HealthSnapshot, now: Date, calendar: Calendar = .current) -> Bool {
        let today = QueryDates.dayString(for: now, calendar: calendar)
        let present = Self.dailyScores.contains { metric in
            guard let reading = snapshot.readings[metric] else { return false }
            return reading.availability == .available && reading.score != nil && reading.sourceDay == today
        }
        if !present {
            if snapshot.hasData || !snapshot.readings.isEmpty { missingDay = today }
            return false
        }
        guard missingDay == today, announcedDay != today else { return false }
        announcedDay = today
        return true
    }
}
