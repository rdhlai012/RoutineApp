import Foundation

/// The result of saving one date's prayer times and rescheduling it, checked
/// against what the notification centre actually reports as pending.
public struct ScheduleOutcome: Equatable, Sendable {
    public var dateKey: String
    /// Real count read back from the notification centre, not what we hoped for.
    public var pendingCount: Int
    public var prayersScheduled: [Prayer]
    public var prayersMissing: [Prayer]
    public var truncated: Int
    /// Wall-clock moment the save happened.
    public var savedAt: TimeOfDay?

    public init(dateKey: String,
                pendingCount: Int,
                prayersScheduled: [Prayer],
                prayersMissing: [Prayer],
                truncated: Int = 0,
                savedAt: TimeOfDay? = nil) {
        self.dateKey = dateKey
        self.pendingCount = pendingCount
        self.prayersScheduled = prayersScheduled
        self.prayersMissing = prayersMissing
        self.truncated = truncated
        self.savedAt = savedAt
    }

    public var isSuccess: Bool { prayersMissing.isEmpty }

    /// "Tomorrow scheduled ✓ Fajr, Dhuhr, Asr, Maghrib, Isha (23 reminders)"
    /// or an explicit error when read-back found a prayer missing.
    public func message(label: String) -> String {
        let names = prayersScheduled.map(\.displayName).joined(separator: ", ")
        if !isSuccess {
            let missing = prayersMissing.map(\.displayName).joined(separator: ", ")
            return "\(label) is NOT fully scheduled. Missing: \(missing). "
                + "Check Settings > Notifications and try saving again."
        }
        var text = "\(label) scheduled ✓ \(names) (\(pendingCount) reminders)"
        if let savedAt = savedAt {
            text += " · saved \(savedAt.description)"
        }
        if truncated > 0 {
            text += " · \(truncated) later reminders were skipped to stay under the iOS limit"
        }
        return text
    }
}

/// Pure logic for the "Set Up Tomorrow" flow. The view owns the draft; this
/// type owns the rules, so all of it is testable without UserNotifications.
public enum TomorrowSetup {
    /// Save is only allowed once all five are entered AND in valid order.
    public static func validate(_ draft: PrayerTimesDraft)
        -> Result<PrayerTimes, PrayerTimesValidationError> {
        PrayerTimesValidator.validate(draft)
    }

    public static func canSave(_ draft: PrayerTimesDraft) -> Bool {
        if case .success = validate(draft) { return true }
        return false
    }

    /// Explains exactly why the save button is off, for the UI to show.
    public static func saveBlockedReason(_ draft: PrayerTimesDraft) -> String? {
        switch validate(draft) {
        case .success: return nil
        case .failure(let error): return error.message
        }
    }

    /// A preview of the whole day as it would be once these times are saved,
    /// without touching stored data.
    public static func preview(dateKey: String, times: PrayerTimes, data: RoutineData)
        -> (schedule: [PlannedTask], conflicts: [ScheduleConflict]) {
        var probe = data
        probe.mutateDay(dateKey) { $0.prayerTimes = times }
        return (Planner.plan(dateKey: dateKey, data: probe),
                ConflictChecker.check(dateKey: dateKey, data: probe))
    }

    /// The identifier every obligatory prayer MUST have pending for `dateKey`.
    public static func requiredPrayerIdentifiers(dateKey: String, data: RoutineData) -> [Prayer: String] {
        var result: [Prayer: String] = [:]
        for prayer in Prayer.allCases {
            guard let task = data.tasks.first(where: { $0.protectedPrayer == prayer }) else { continue }
            result[prayer] = NotificationID.dated(task: task.id, dateKey: dateKey, burst: 0)
        }
        return result
    }

    /// Read-back check. `pendingIdentifiers` comes straight from
    /// `getPendingNotificationRequests`, so this is what is really scheduled.
    public static func verify(pendingIdentifiers: [String],
                              dateKey: String,
                              data: RoutineData,
                              truncated: Int = 0,
                              savedAt: TimeOfDay? = nil) -> ScheduleOutcome {
        let pending = Set(pendingIdentifiers)
        let required = requiredPrayerIdentifiers(dateKey: dateKey, data: data)

        var scheduled: [Prayer] = []
        var missing: [Prayer] = []
        for prayer in Prayer.allCases {
            guard let identifier = required[prayer] else {
                missing.append(prayer)
                continue
            }
            if pending.contains(identifier) {
                scheduled.append(prayer)
            } else {
                missing.append(prayer)
            }
        }

        let count = NotificationID.matchingTasks(pendingIdentifiers, dateKey: dateKey).count
        return ScheduleOutcome(dateKey: dateKey,
                               pendingCount: count,
                               prayersScheduled: scheduled,
                               prayersMissing: missing,
                               truncated: truncated,
                               savedAt: savedAt)
    }
}
