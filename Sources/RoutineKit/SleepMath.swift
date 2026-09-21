import Foundation

public enum SleepStatus: String, Equatable, Sendable {
    case belowMinimum
    case meetsMinimum
    case meetsGoal

    public var displayName: String {
        switch self {
        case .belowMinimum: return "Below minimum"
        case .meetsMinimum: return "Meets minimum"
        case .meetsGoal: return "Meets goal"
        }
    }
}

public struct SleepSummary: Equatable, Sendable {
    public var nightsLogged: Int
    public var averageMinutes: Int
    public var nightsMeetingMinimum: Int
    public var nightsMeetingGoal: Int

    public init(nightsLogged: Int, averageMinutes: Int, nightsMeetingMinimum: Int, nightsMeetingGoal: Int) {
        self.nightsLogged = nightsLogged
        self.averageMinutes = averageMinutes
        self.nightsMeetingMinimum = nightsMeetingMinimum
        self.nightsMeetingGoal = nightsMeetingGoal
    }

    public var averageDescription: String { SleepMath.describe(minutes: averageMinutes) }
}

public enum SleepMath {
    /// "6h 40m" / "45m"
    public static func describe(minutes: Int) -> String {
        let safe = max(0, minutes)
        let h = safe / 60
        let m = safe % 60
        if h == 0 { return "\(m)m" }
        return "\(h)h \(String(format: "%02d", m))m"
    }

    /// Build a log that ends at `wake` and lasted `minutes`, wrapping midnight.
    public static func log(endingAt wake: TimeOfDay, lastingMinutes minutes: Int) -> SleepLog {
        SleepLog(bedtime: wake.adding(minutes: -minutes), wakeTime: wake)
    }

    /// wake - goal. 04:50 - 7h = 21:50.
    public static func targetBedtime(wake: TimeOfDay, goalMinutes: Int) -> TimeOfDay {
        wake.adding(minutes: -goalMinutes)
    }

    /// wake - minimum. 04:50 - 6h = 22:50.
    public static func latestBedtime(wake: TimeOfDay, minimumMinutes: Int) -> TimeOfDay {
        wake.adding(minutes: -minimumMinutes)
    }

    public static func status(durationMinutes: Int, minimumMinutes: Int, goalMinutes: Int) -> SleepStatus {
        if durationMinutes >= goalMinutes { return .meetsGoal }
        if durationMinutes >= minimumMinutes { return .meetsMinimum }
        return .belowMinimum
    }

    public static func status(_ log: SleepLog, settings: RoutineSettings) -> SleepStatus {
        status(durationMinutes: log.durationMinutes,
               minimumMinutes: settings.minimumSleepMinutes,
               goalMinutes: settings.goalSleepMinutes)
    }

    /// Averages over the logs given (caller picks the window, e.g. last 7 days).
    public static func summarise(_ logs: [SleepLog], settings: RoutineSettings) -> SleepSummary {
        guard !logs.isEmpty else {
            return SleepSummary(nightsLogged: 0, averageMinutes: 0,
                                nightsMeetingMinimum: 0, nightsMeetingGoal: 0)
        }
        let durations = logs.map(\.durationMinutes)
        let total = durations.reduce(0, +)
        let minimum = durations.filter { $0 >= settings.minimumSleepMinutes }.count
        let goal = durations.filter { $0 >= settings.goalSleepMinutes }.count
        return SleepSummary(nightsLogged: logs.count,
                            averageMinutes: total / logs.count,
                            nightsMeetingMinimum: minimum,
                            nightsMeetingGoal: goal)
    }
}
