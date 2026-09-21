import Foundation

/// How a scheduled reminder should sound.
public enum NotificationSound: String, Equatable, Sendable {
    /// No sound at all - the task has its alarm switched off.
    case silent
    /// The system default notification sound.
    case standard
    /// The bundled 28-second alarm.wav (wake-up only).
    case alarmFile

    public static let alarmFileName = "alarm.wav"
}

/// One task placed on one date.
public struct PlannedTask: Equatable, Identifiable, Sendable {
    public var task: RoutineTask
    /// Nil when the task is prayer-anchored and that date has no exact times.
    public var time: TimeOfDay?
    /// Set only when `time` is nil.
    public var unresolvedReason: String?

    public var id: UUID { task.id }
    public var isResolved: Bool { time != nil }

    public init(task: RoutineTask, time: TimeOfDay?, unresolvedReason: String? = nil) {
        self.task = task
        self.time = time
        self.unresolvedReason = unresolvedReason
    }

    public static let noPrayerTimesReason = "No prayer times"
}

/// A notification request described in pure Foundation terms. The
/// UserNotifications wrapper turns one of these into one UNNotificationRequest
/// and does no decision-making of its own.
public struct PlannedNotification: Equatable, Hashable, Identifiable, Sendable {
    public var identifier: String
    public var taskID: UUID
    public var title: String
    public var body: String
    public var sound: NotificationSound
    /// Trigger components. Year/month/day present for a one-off; hour/minute
    /// only when `repeatsDaily` is true.
    public var dateComponents: DateComponents
    public var repeatsDaily: Bool
    /// yyyy-MM-dd for date-specific requests, nil for daily repeating ones.
    public var dateKey: String?
    public var burstIndex: Int
    /// Concrete next fire moment, used only for ordering and the 60 cap.
    public var nextFireDate: Date?

    public var id: String { identifier }

    public init(identifier: String,
                taskID: UUID,
                title: String,
                body: String,
                sound: NotificationSound,
                dateComponents: DateComponents,
                repeatsDaily: Bool,
                dateKey: String?,
                burstIndex: Int,
                nextFireDate: Date?) {
        self.identifier = identifier
        self.taskID = taskID
        self.title = title
        self.body = body
        self.sound = sound
        self.dateComponents = dateComponents
        self.repeatsDaily = repeatsDaily
        self.dateKey = dateKey
        self.burstIndex = burstIndex
        self.nextFireDate = nextFireDate
    }
}

/// Everything about notification identifiers lives here so that "scoped
/// removal" can be reasoned about and tested without UserNotifications.
public enum NotificationID {
    public static let prefix = "routine."

    public static func isRoutine(_ identifier: String) -> Bool {
        identifier.hasPrefix(prefix)
    }

    /// routine.<taskUUID>.<yyyy-MM-dd>.<burstIndex>
    public static func dated(task: UUID, dateKey: String, burst: Int) -> String {
        "\(prefix)\(task.uuidString).\(dateKey).\(burst)"
    }

    /// routine.<taskUUID>.daily.<burstIndex>
    public static func daily(task: UUID, burst: Int) -> String {
        "\(prefix)\(task.uuidString).daily.\(burst)"
    }

    /// routine.nudge.<yyyy-MM-dd>
    public static func nudge(dateKey: String) -> String {
        "\(prefix)nudge.\(dateKey)"
    }

    public static func taskID(in identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 3, parts[0] == "routine" else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    /// nil for daily requests and for the nudge.
    public static func dateKey(in identifier: String) -> String? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 3, parts[0] == "routine" else { return nil }
        if parts[1] == "nudge" { return String(parts[2]) }
        let candidate = String(parts[2])
        return candidate == "daily" ? nil : candidate
    }

    public static func isDaily(_ identifier: String) -> Bool {
        identifier.split(separator: ".").dropFirst(2).first == "daily"
    }

    public static func isNudge(_ identifier: String) -> Bool {
        identifier.split(separator: ".").dropFirst(1).first == "nudge"
    }

    /// The "Send test alarm" reminder. Ours by prefix, but never part of the
    /// planned schedule, so reconciliation must leave it alone.
    public static let test = prefix + "test.alarm"

    public static func isTest(_ identifier: String) -> Bool {
        identifier == test
    }

    // MARK: Scoped selection

    /// Every routine identifier belonging to one date, nudge included.
    /// Anything that is not ours is never returned.
    public static func matching(_ identifiers: [String], dateKey: String) -> [String] {
        identifiers.filter { isRoutine($0) && Self.dateKey(in: $0) == dateKey }
    }

    /// Date-specific identifiers for one date, EXCLUDING the nudge.
    public static func matchingTasks(_ identifiers: [String], dateKey: String) -> [String] {
        identifiers.filter { isRoutine($0) && !isNudge($0) && Self.dateKey(in: $0) == dateKey }
    }

    public static func matching(_ identifiers: [String], task: UUID) -> [String] {
        identifiers.filter { isRoutine($0) && taskID(in: $0) == task }
    }

    public static func matchingDaily(_ identifiers: [String]) -> [String] {
        identifiers.filter { isRoutine($0) && isDaily($0) }
    }
}

public enum Planner {
    /// iOS keeps at most 64 pending requests; we stay under it on purpose.
    public static let pendingLimit = 60
    /// Bursts for an insistent alarm, one minute apart.
    public static let insistentBursts = 5

    // MARK: - Placing tasks on a date

    /// Every enabled task that applies to `dateKey`, sorted by time.
    /// Prayer-anchored tasks on a date with no saved times come back
    /// unresolved - they are NEVER computed from another date.
    public static func plan(dateKey: String, data: RoutineData) -> [PlannedTask] {
        let goingOut = data.isGoingOut(on: dateKey)
        let times = data.prayerTimes(on: dateKey)

        var planned: [PlannedTask] = []
        for task in data.tasks {
            guard task.enabled else { continue }
            if task.onlyWhenGoingOut && !goingOut { continue }

            switch task.timing {
            case .fixed(let time):
                planned.append(PlannedTask(task: task, time: time))
            case .anchored(let prayer, let offset):
                guard let times = times else {
                    planned.append(PlannedTask(task: task, time: nil,
                                               unresolvedReason: PlannedTask.noPrayerTimesReason))
                    continue
                }
                planned.append(PlannedTask(task: task, time: times[prayer].adding(minutes: offset)))
            }
        }
        return sorted(planned)
    }

    /// In routine order (the order tasks are stored in), which is the order the
    /// day is *meant* to happen in. Used by the conflict checker.
    public static func planInRoutineOrder(dateKey: String, data: RoutineData) -> [PlannedTask] {
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`: a hand-edited
        // file could carry a duplicated task id, and that must not trap.
        let byID = Dictionary(plan(dateKey: dateKey, data: data).map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        return data.tasks.compactMap { byID[$0.id] }
    }

    /// Time order; unresolved tasks sink to the bottom, stable by title.
    public static func sorted(_ planned: [PlannedTask]) -> [PlannedTask] {
        planned.enumerated().sorted { lhs, rhs in
            switch (lhs.element.time, rhs.element.time) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.offset < rhs.offset
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    // MARK: - Turning tasks into notifications

    private static func sound(for task: RoutineTask) -> NotificationSound {
        guard task.alarm else { return .silent }
        return task.insistent ? .alarmFile : .standard
    }

    private static func body(for task: RoutineTask, at time: TimeOfDay) -> String {
        if let note = task.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(time.description) - \(note)"
        }
        return time.description
    }

    private static func burstCount(for task: RoutineTask) -> Int {
        task.insistent ? insistentBursts : 1
    }

    /// Fixed-time tasks that are not going-out-only: scheduled as repeating
    /// daily reminders so they still fire when the app is never opened.
    public static func dailyNotifications(data: RoutineData,
                                          calendar: Calendar = .current,
                                          now: Date = Date()) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        for task in data.tasks {
            guard task.enabled, !task.onlyWhenGoingOut,
                  let time = task.timing.fixedTime else { continue }
            for burst in 0..<burstCount(for: task) {
                let fireTime = time.adding(minutes: burst)
                var comps = DateComponents()
                comps.hour = fireTime.hour
                comps.minute = fireTime.minute
                result.append(PlannedNotification(
                    identifier: NotificationID.daily(task: task.id, burst: burst),
                    taskID: task.id,
                    title: task.title,
                    body: body(for: task, at: fireTime),
                    sound: sound(for: task),
                    dateComponents: comps,
                    repeatsDaily: true,
                    dateKey: nil,
                    burstIndex: burst,
                    nextFireDate: calendar.nextDate(after: now,
                                                    matching: comps,
                                                    matchingPolicy: .nextTime)
                ))
            }
        }
        return result
    }

    /// Everything that belongs to one specific date: all prayer-anchored tasks
    /// (only if that date has exact times) plus going-out-only tasks.
    /// Past moments relative to `now` are dropped.
    public static func dateNotifications(dateKey: String,
                                         data: RoutineData,
                                         calendar: Calendar = .current,
                                         now: Date = Date(),
                                         includePast: Bool = false) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        for planned in plan(dateKey: dateKey, data: data) {
            let task = planned.task
            let isDateSpecific = task.timing.isAnchored || task.onlyWhenGoingOut
            guard isDateSpecific, let time = planned.time else { continue }

            for burst in 0..<burstCount(for: task) {
                let fireTime = time.adding(minutes: burst)
                guard let comps = calendar.components(forKey: dateKey, at: fireTime),
                      let fireDate = calendar.date(from: comps) else { continue }
                if !includePast && fireDate <= now { continue }
                result.append(PlannedNotification(
                    identifier: NotificationID.dated(task: task.id, dateKey: dateKey, burst: burst),
                    taskID: task.id,
                    title: task.title,
                    body: body(for: task, at: fireTime),
                    sound: sound(for: task),
                    dateComponents: comps,
                    repeatsDaily: false,
                    dateKey: dateKey,
                    burstIndex: burst,
                    nextFireDate: fireDate
                ))
            }
        }
        return result.sorted { ($0.nextFireDate ?? .distantFuture) < ($1.nextFireDate ?? .distantFuture) }
    }

    /// The one-off "enter tomorrow's prayer times" nudge, at today's Maghrib
    /// plus the configured offset. Nil when today has no Maghrib time, or when
    /// tomorrow's times are already saved, or when the moment has passed.
    public static func nudgeNotification(dateKey: String,
                                         data: RoutineData,
                                         calendar: Calendar = .current,
                                         now: Date = Date()) -> PlannedNotification? {
        guard let times = data.prayerTimes(on: dateKey) else { return nil }
        guard let tomorrow = DateKey.offset(dateKey, byDays: 1, calendar: calendar) else { return nil }
        guard data.prayerTimes(on: tomorrow) == nil else { return nil }

        let fireTime = times.maghrib.adding(minutes: data.settings.nudgeOffsetAfterMaghrib)
        guard fireTime > times.maghrib else { return nil }   // would spill past midnight
        guard let comps = calendar.components(forKey: dateKey, at: fireTime),
              let fireDate = calendar.date(from: comps), fireDate > now else { return nil }

        return PlannedNotification(
            identifier: NotificationID.nudge(dateKey: dateKey),
            taskID: DefaultTaskID.sleepReminder,   // not task-driven; kept stable for filtering
            title: "Enter tomorrow's prayer times",
            body: "Open Routine and set up \(DateKey.longDisplay(tomorrow, calendar: calendar)).",
            sound: .standard,
            dateComponents: comps,
            repeatsDaily: false,
            dateKey: dateKey,
            burstIndex: 0,
            nextFireDate: fireDate
        )
    }

    /// The complete set the app wants pending: daily repeats + the next
    /// `horizonDays` dates + today's nudge.
    public static func fullSchedule(data: RoutineData,
                                    calendar: Calendar = .current,
                                    now: Date = Date(),
                                    horizonDays: Int = 3) -> [PlannedNotification] {
        var result = dailyNotifications(data: data, calendar: calendar, now: now)
        let today = DateKey.string(from: now, calendar: calendar)
        for offset in 0...max(0, horizonDays) {
            guard let key = DateKey.offset(today, byDays: offset, calendar: calendar) else { continue }
            result += dateNotifications(dateKey: key, data: data, calendar: calendar, now: now)
        }
        if let nudge = nudgeNotification(dateKey: today, data: data, calendar: calendar, now: now) {
            result.append(nudge)
        }
        return result
    }

    // MARK: - The 64-request limit

    public struct CapResult: Equatable, Sendable {
        public var kept: [PlannedNotification]
        public var truncated: Int
        public var didTruncate: Bool { truncated > 0 }
    }

    /// Keeps the soonest `limit` requests and reports how many were dropped.
    public static func cap(_ notifications: [PlannedNotification],
                           limit: Int = Planner.pendingLimit) -> CapResult {
        let unique = deduplicate(notifications)
        let ordered = unique.sorted {
            let l = $0.nextFireDate ?? .distantFuture
            let r = $1.nextFireDate ?? .distantFuture
            if l != r { return l < r }
            return $0.identifier < $1.identifier
        }
        guard ordered.count > limit else { return CapResult(kept: ordered, truncated: 0) }
        return CapResult(kept: Array(ordered.prefix(limit)),
                         truncated: ordered.count - limit)
    }

    // MARK: - Reconciling against what is really pending

    public struct Reconciliation: Equatable, Sendable {
        /// Only ever "routine." identifiers, never the test alarm.
        public var toRemove: [String]
        /// Re-adding an existing identifier replaces it in place, so this is
        /// the whole desired set and can never create a duplicate.
        public var toAdd: [PlannedNotification]
    }

    /// Works out the smallest scoped change that turns `pending` into `desired`.
    /// Anything that is not ours is left completely untouched.
    public static func reconcile(pending: [String],
                                 desired: [PlannedNotification]) -> Reconciliation {
        let wanted = Set(desired.map(\.identifier))
        let stale = pending.filter {
            NotificationID.isRoutine($0) && !NotificationID.isTest($0) && !wanted.contains($0)
        }
        return Reconciliation(toRemove: stale, toAdd: desired)
    }

    /// Same identifier twice means the same reminder: the first wins.
    public static func deduplicate(_ notifications: [PlannedNotification]) -> [PlannedNotification] {
        var seen = Set<String>()
        var result: [PlannedNotification] = []
        for item in notifications where seen.insert(item.identifier).inserted {
            result.append(item)
        }
        return result
    }
}
