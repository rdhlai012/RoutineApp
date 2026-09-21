import Foundation

public struct RoutineSettings: Codable, Hashable, Sendable {
    /// Day 1 of the routine, yyyy-MM-dd.
    public var startDateKey: String
    public var minimumSleepMinutes: Int
    public var goalSleepMinutes: Int
    /// Single source of truth for the morning. The "Wake up" task is kept in
    /// sync with this value by `RoutineData.applyWakeTimeToWakeTask()`.
    public var wakeTime: TimeOfDay
    /// A day counts as "good" at or above this completion fraction.
    public var goodDayThreshold: Double
    /// Minutes after Maghrib for the "enter tomorrow's times" nudge.
    public var nudgeOffsetAfterMaghrib: Int

    public static let defaultWakeTime = TimeOfDay(hour: 4, minute: 50)

    public init(startDateKey: String,
                minimumSleepMinutes: Int = 6 * 60,
                goalSleepMinutes: Int = 7 * 60,
                wakeTime: TimeOfDay = RoutineSettings.defaultWakeTime,
                goodDayThreshold: Double = 0.8,
                nudgeOffsetAfterMaghrib: Int = 15) {
        self.startDateKey = startDateKey
        self.minimumSleepMinutes = minimumSleepMinutes
        self.goalSleepMinutes = goalSleepMinutes
        self.wakeTime = wakeTime
        self.goodDayThreshold = goodDayThreshold
        self.nudgeOffsetAfterMaghrib = nudgeOffsetAfterMaghrib
    }

    public var targetBedtime: TimeOfDay {
        SleepMath.targetBedtime(wake: wakeTime, goalMinutes: goalSleepMinutes)
    }

    public var latestBedtime: TimeOfDay {
        SleepMath.latestBedtime(wake: wakeTime, minimumMinutes: minimumSleepMinutes)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startDateKey = try c.decodeIfPresent(String.self, forKey: .startDateKey)
            ?? c.decodeIfPresent(String.self, forKey: .startDate)
            ?? ""
        minimumSleepMinutes = try c.decodeIfPresent(Int.self, forKey: .minimumSleepMinutes) ?? 6 * 60
        goalSleepMinutes = try c.decodeIfPresent(Int.self, forKey: .goalSleepMinutes) ?? 7 * 60
        wakeTime = try c.decodeIfPresent(TimeOfDay.self, forKey: .wakeTime)
            ?? RoutineSettings.defaultWakeTime
        goodDayThreshold = try c.decodeIfPresent(Double.self, forKey: .goodDayThreshold) ?? 0.8
        nudgeOffsetAfterMaghrib = try c.decodeIfPresent(Int.self, forKey: .nudgeOffsetAfterMaghrib) ?? 15
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startDateKey, forKey: .startDateKey)
        try c.encode(minimumSleepMinutes, forKey: .minimumSleepMinutes)
        try c.encode(goalSleepMinutes, forKey: .goalSleepMinutes)
        try c.encode(wakeTime, forKey: .wakeTime)
        try c.encode(goodDayThreshold, forKey: .goodDayThreshold)
        try c.encode(nudgeOffsetAfterMaghrib, forKey: .nudgeOffsetAfterMaghrib)
    }

    private enum CodingKeys: String, CodingKey {
        case startDateKey, minimumSleepMinutes, goalSleepMinutes
        case wakeTime, goodDayThreshold, nudgeOffsetAfterMaghrib
        // Legacy, read-only:
        case startDate
    }
}
