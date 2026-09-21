import Foundation

/// The one-line observation shown on Today's insight card. Pure logic so the
/// wording and the thresholds are unit tested rather than guessed at in a view.
public struct DailyInsight: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case noPrayerTimes
        case allDone
        case ahead
        case level
        case behind
        case firstDay
    }

    public var kind: Kind
    public var headline: String
    public var detail: String

    public init(kind: Kind, headline: String, detail: String) {
        self.kind = kind
        self.headline = headline
        self.detail = detail
    }

    /// SF Symbol for the card. Orange is reserved for prayer matters, so only
    /// `.noPrayerTimes` gets a prayer-flavoured icon.
    public var symbolName: String {
        switch kind {
        case .noPrayerTimes: return "moon.stars"
        case .allDone: return "checkmark.seal.fill"
        case .ahead: return "chart.line.uptrend.xyaxis"
        case .level: return "equal.circle"
        case .behind: return "arrow.down.right.circle"
        case .firstDay: return "sparkles"
        }
    }
}

public enum InsightEngine {

    /// Compares today with the same date a day earlier. Deliberately compares
    /// completed COUNTS, not percentages: the number of tasks in a day changes
    /// when going-out is on, and a raw count is what the person actually feels.
    public static func insight(on dateKey: String,
                               data: RoutineData,
                               calendar: Calendar = .current) -> DailyInsight {
        let today = Stats.completion(dateKey: dateKey, data: data)

        if data.prayerTimes(on: dateKey) == nil {
            return DailyInsight(
                kind: .noPrayerTimes,
                headline: "Prayer times needed",
                detail: "Nothing prayer-anchored is scheduled until you enter them.")
        }

        if today.plannedCount > 0 && today.completedCount >= today.plannedCount {
            return DailyInsight(
                kind: .allDone,
                headline: "Day complete",
                detail: "Every one of the \(today.plannedCount) tasks is done.")
        }

        guard let yesterdayKey = DateKey.offset(dateKey, byDays: -1, calendar: calendar) else {
            return DailyInsight(kind: .firstDay,
                                headline: "Keep going",
                                detail: "\(remaining(today)) still to go today.")
        }

        let yesterday = Stats.completion(dateKey: yesterdayKey, data: data)
        guard yesterday.plannedCount > 0 else {
            return DailyInsight(
                kind: .firstDay,
                headline: "First day tracked",
                detail: "\(remaining(today)) still to go today.")
        }

        let difference = today.completedCount - yesterday.completedCount
        if difference > 0 {
            return DailyInsight(
                kind: .ahead,
                headline: "Ahead of yesterday",
                detail: "\(today.completedCount) done against \(yesterday.completedCount) yesterday.")
        }
        if difference == 0 {
            return DailyInsight(
                kind: .level,
                headline: "Level with yesterday",
                detail: "\(today.completedCount) done, same as yesterday.")
        }
        return DailyInsight(
            kind: .behind,
            headline: "Behind yesterday",
            detail: "\(-difference) \(pluralise(-difference, "task")) behind yesterday's \(yesterday.completedCount).")
    }

    private static func remaining(_ completion: DayCompletion) -> String {
        let left = max(0, completion.plannedCount - completion.completedCount)
        return "\(left) \(pluralise(left, "task"))"
    }

    private static func pluralise(_ count: Int, _ word: String) -> String {
        count == 1 ? word : word + "s"
    }
}
