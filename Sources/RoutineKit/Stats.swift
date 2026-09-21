import Foundation

public enum DayState: String, Equatable, Sendable {
    case complete      // 100%
    case partial       // > 0% and < 100%
    case missed        // 0% with tasks planned
    case noData        // nothing planned / nothing known

    public var displayName: String {
        switch self {
        case .complete: return "Complete"
        case .partial: return "Partial"
        case .missed: return "Missed"
        case .noData: return "No data"
        }
    }
}

public struct DayCompletion: Equatable, Sendable {
    public var dateKey: String
    public var plannedCount: Int
    public var completedCount: Int

    public init(dateKey: String, plannedCount: Int, completedCount: Int) {
        self.dateKey = dateKey
        self.plannedCount = plannedCount
        self.completedCount = completedCount
    }

    /// 0...1. A day with nothing planned is 0.
    public var fraction: Double {
        guard plannedCount > 0 else { return 0 }
        return Double(completedCount) / Double(plannedCount)
    }

    public var percent: Int { Int((fraction * 100).rounded()) }

    public var state: DayState {
        guard plannedCount > 0 else { return .noData }
        if completedCount >= plannedCount { return .complete }
        if completedCount > 0 { return .partial }
        return .missed
    }
}

public struct RoutineStats: Equatable, Sendable {
    public var dayNumber: Int
    public var currentStreak: Int
    public var longestStreak: Int
    public var goodDays: Int
    public var daysRecorded: Int

    public init(dayNumber: Int, currentStreak: Int, longestStreak: Int,
                goodDays: Int, daysRecorded: Int) {
        self.dayNumber = dayNumber
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.goodDays = goodDays
        self.daysRecorded = daysRecorded
    }
}

public enum Stats {
    /// Tasks that counted towards the day, i.e. everything the planner placed
    /// AND resolved. An unresolved prayer-anchored task cannot be failed.
    public static func completion(dateKey: String, data: RoutineData) -> DayCompletion {
        let planned = Planner.plan(dateKey: dateKey, data: data).filter { $0.isResolved }
        let done = data.day(dateKey)?.completedTaskIDs ?? []
        let completed = planned.filter { done.contains($0.id) }.count
        return DayCompletion(dateKey: dateKey,
                             plannedCount: planned.count,
                             completedCount: completed)
    }

    /// Day 1 is the start date itself.
    public static func dayNumber(on dateKey: String, data: RoutineData,
                                 calendar: Calendar = .current) -> Int {
        guard let diff = DateKey.daysBetween(data.settings.startDateKey, dateKey, calendar: calendar)
        else { return 1 }
        return max(1, diff + 1)
    }

    public static func isGoodDay(_ completion: DayCompletion, threshold: Double) -> Bool {
        completion.plannedCount > 0 && completion.fraction + 1e-9 >= threshold
    }

    /// Every day from the start date up to and including `today`.
    public static func completions(upTo today: String, data: RoutineData,
                                   calendar: Calendar = .current) -> [DayCompletion] {
        guard let span = DateKey.daysBetween(data.settings.startDateKey, today, calendar: calendar),
              span >= 0 else { return [] }
        var result: [DayCompletion] = []
        for offset in 0...span {
            guard let key = DateKey.offset(data.settings.startDateKey, byDays: offset, calendar: calendar)
            else { continue }
            result.append(completion(dateKey: key, data: data))
        }
        return result
    }

    /// Consecutive good days ending at `today`. Today is allowed to still be in
    /// progress: if it is not good yet, the streak is measured to yesterday.
    public static func currentStreak(upTo today: String, data: RoutineData,
                                     calendar: Calendar = .current) -> Int {
        let threshold = data.settings.goodDayThreshold
        let series = completions(upTo: today, data: data, calendar: calendar)
        guard !series.isEmpty else { return 0 }

        var index = series.count - 1
        if !isGoodDay(series[index], threshold: threshold) {
            index -= 1   // today still in progress
        }
        var streak = 0
        while index >= 0, isGoodDay(series[index], threshold: threshold) {
            streak += 1
            index -= 1
        }
        return streak
    }

    public static func longestStreak(upTo today: String, data: RoutineData,
                                     calendar: Calendar = .current) -> Int {
        let threshold = data.settings.goodDayThreshold
        var best = 0
        var run = 0
        for day in completions(upTo: today, data: data, calendar: calendar) {
            if isGoodDay(day, threshold: threshold) {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return best
    }

    public static func summary(upTo today: String, data: RoutineData,
                               calendar: Calendar = .current) -> RoutineStats {
        let threshold = data.settings.goodDayThreshold
        let series = completions(upTo: today, data: data, calendar: calendar)
        return RoutineStats(
            dayNumber: dayNumber(on: today, data: data, calendar: calendar),
            currentStreak: currentStreak(upTo: today, data: data, calendar: calendar),
            longestStreak: longestStreak(upTo: today, data: data, calendar: calendar),
            goodDays: series.filter { isGoodDay($0, threshold: threshold) }.count,
            daysRecorded: series.count)
    }

    /// The last `count` nights that have a sleep log, most recent last.
    public static func recentSleep(upTo today: String, data: RoutineData,
                                   count: Int = 7,
                                   calendar: Calendar = .current) -> [SleepLog] {
        var logs: [SleepLog] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let key = DateKey.offset(today, byDays: -offset, calendar: calendar),
                  let log = data.day(key)?.sleep else { continue }
            logs.append(log)
        }
        return logs
    }
}
