import Foundation

public struct ScheduleConflict: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// A task that should come later in the routine lands earlier in the day.
        case outOfSequence
        /// Isha falls after the gym slot, so the gym would run before the prayer.
        case prayerAfterGym
        /// Two tasks land on exactly the same minute.
        case collision
    }

    public var kind: Kind
    public var message: String
    public var firstTaskID: UUID
    public var secondTaskID: UUID

    public var id: String { "\(kind.rawValue)-\(firstTaskID)-\(secondTaskID)" }

    public init(kind: Kind, message: String, firstTaskID: UUID, secondTaskID: UUID) {
        self.kind = kind
        self.message = message
        self.firstTaskID = firstTaskID
        self.secondTaskID = secondTaskID
    }
}

public enum ConflictChecker {
    /// Walks the routine in its intended order and flags anywhere the clock
    /// goes backwards, e.g. "Wudu 4:48 AM is before Bath 5:00 AM."
    public static func check(dateKey: String, data: RoutineData) -> [ScheduleConflict] {
        let ordered = Planner.planInRoutineOrder(dateKey: dateKey, data: data)
            .filter { $0.time != nil }

        var conflicts: [ScheduleConflict] = []
        var previous: PlannedTask?
        for planned in ordered {
            defer { previous = planned }
            guard let earlier = previous,
                  let earlierTime = earlier.time,
                  let time = planned.time else { continue }
            if time < earlierTime {
                conflicts.append(ScheduleConflict(
                    kind: .outOfSequence,
                    message: "\(planned.task.title) \(time.description) is before "
                        + "\(earlier.task.title) \(earlierTime.description).",
                    firstTaskID: earlier.id,
                    secondTaskID: planned.id))
            } else if time == earlierTime {
                conflicts.append(ScheduleConflict(
                    kind: .collision,
                    message: "\(planned.task.title) and \(earlier.task.title) are both at "
                        + "\(time.description).",
                    firstTaskID: earlier.id,
                    secondTaskID: planned.id))
            }
        }

        conflicts += checkIshaAgainstGym(dateKey: dateKey, data: data)
        return conflicts
    }

    /// The gym is meant to come after the prayers, so Isha landing after the
    /// gym slot is worth flagging on its own.
    public static func checkIshaAgainstGym(dateKey: String, data: RoutineData) -> [ScheduleConflict] {
        guard let times = data.prayerTimes(on: dateKey) else { return [] }
        guard let ishaTask = data.tasks.first(where: { $0.protectedPrayer == .isha }) else { return [] }
        guard let gym = data.tasks.first(where: { $0.category == .gym && $0.enabled }),
              let gymTime = gym.timing.fixedTime else { return [] }

        let ishaTime = times.isha.adding(minutes: ishaTask.timing.offset)
        guard ishaTime > gymTime else { return [] }
        return [ScheduleConflict(
            kind: .prayerAfterGym,
            message: "Isha \(ishaTime.description) falls after \(gym.title) "
                + "\(gymTime.description). The gym is meant to come after the prayers.",
            firstTaskID: gym.id,
            secondTaskID: ishaTask.id)]
    }
}
