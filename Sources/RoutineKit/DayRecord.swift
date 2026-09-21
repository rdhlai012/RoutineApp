import Foundation

/// One night's sleep, logged against the date you WOKE UP on.
public struct SleepLog: Codable, Hashable, Sendable {
    public var bedtime: TimeOfDay
    public var wakeTime: TimeOfDay

    public init(bedtime: TimeOfDay, wakeTime: TimeOfDay) {
        self.bedtime = bedtime
        self.wakeTime = wakeTime
    }

    /// Cross-midnight aware. 22:10 -> 04:50 is 400 minutes (6h 40m).
    public var durationMinutes: Int {
        if wakeTime.minutes >= bedtime.minutes {
            return wakeTime.minutes - bedtime.minutes
        }
        return wakeTime.minutes + 1440 - bedtime.minutes
    }

    /// "6h 40m"
    public var durationDescription: String {
        SleepMath.describe(minutes: durationMinutes)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bedtime = try c.decodeIfPresent(TimeOfDay.self, forKey: .bedtime) ?? TimeOfDay(hour: 22, minute: 0)
        wakeTime = try c.decodeIfPresent(TimeOfDay.self, forKey: .wakeTime) ?? TimeOfDay(hour: 4, minute: 50)
    }

    private enum CodingKeys: String, CodingKey {
        case bedtime, wakeTime
    }
}

/// Everything recorded against one calendar date.
public struct DayRecord: Codable, Hashable, Sendable {
    /// yyyy-MM-dd
    public var dateKey: String

    /// The EXACT adhan times for this date. `nil` means "not entered" and is
    /// never filled in from another date. There is no fallback anywhere.
    public var prayerTimes: PrayerTimes?

    /// Per-date, defaults to false so every new date starts OFF.
    public var goingOut: Bool

    public var completedTaskIDs: Set<UUID>
    /// Checklist steps ticked, keyed by task id.
    public var completedStepIDs: [UUID: Set<UUID>]
    public var sleep: SleepLog?
    public var note: String?

    public init(dateKey: String,
                prayerTimes: PrayerTimes? = nil,
                goingOut: Bool = false,
                completedTaskIDs: Set<UUID> = [],
                completedStepIDs: [UUID: Set<UUID>] = [:],
                sleep: SleepLog? = nil,
                note: String? = nil) {
        self.dateKey = dateKey
        self.prayerTimes = prayerTimes
        self.goingOut = goingOut
        self.completedTaskIDs = completedTaskIDs
        self.completedStepIDs = completedStepIDs
        self.sleep = sleep
        self.note = note
    }

    public var hasPrayerTimes: Bool { prayerTimes != nil }

    public var isEmpty: Bool {
        prayerTimes == nil && !goingOut && completedTaskIDs.isEmpty
            && completedStepIDs.allSatisfy { $0.value.isEmpty }
            && sleep == nil && (note?.isEmpty ?? true)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? ""
        prayerTimes = try? c.decodeIfPresent(PrayerTimes.self, forKey: .prayerTimes)
        goingOut = try c.decodeIfPresent(Bool.self, forKey: .goingOut) ?? false
        if let stored = try c.decodeIfPresent(Set<UUID>.self, forKey: .completedTaskIDs) {
            completedTaskIDs = stored
        } else {
            let legacy = try c.decodeIfPresent([UUID].self, forKey: .completed) ?? []
            completedTaskIDs = Set(legacy)
        }

        if let raw = try c.decodeIfPresent([String: Set<UUID>].self, forKey: .completedStepIDs) {
            var mapped: [UUID: Set<UUID>] = [:]
            for (key, value) in raw {
                if let uuid = UUID(uuidString: key) { mapped[uuid] = value }
            }
            completedStepIDs = mapped
        } else {
            completedStepIDs = [:]
        }

        if let log = try? c.decodeIfPresent(SleepLog.self, forKey: .sleep) {
            sleep = log
        } else if let hours = try? c.decodeIfPresent(Double.self, forKey: .sleepHours), hours > 0 {
            // v0 migration: only a duration was stored. Anchor it to the default
            // wake time; `RoutineData.migrate` re-anchors it to the real setting.
            sleep = SleepMath.log(endingAt: TimeOfDay(hour: 4, minute: 50),
                                  lastingMinutes: Int((hours * 60).rounded()))
        } else {
            sleep = nil
        }

        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dateKey, forKey: .dateKey)
        try c.encodeIfPresent(prayerTimes, forKey: .prayerTimes)
        try c.encode(goingOut, forKey: .goingOut)
        try c.encode(completedTaskIDs, forKey: .completedTaskIDs)
        var mapped: [String: Set<UUID>] = [:]
        for (key, value) in completedStepIDs where !value.isEmpty {
            mapped[key.uuidString] = value
        }
        try c.encode(mapped, forKey: .completedStepIDs)
        try c.encodeIfPresent(sleep, forKey: .sleep)
        try c.encodeIfPresent(note, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey {
        case dateKey, prayerTimes, goingOut, completedTaskIDs, completedStepIDs, sleep, note
        // Legacy keys, read-only:
        case completed, sleepHours
    }
}
