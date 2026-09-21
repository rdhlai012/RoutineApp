import Foundation

/// The whole persisted document (routine.json).
///
/// Decoding is deliberately tolerant: every field is `decodeIfPresent` with a
/// default, and legacy top-level shapes (a separate `prayerTimes` map, a
/// `sleepHours` number per day) are folded in. A file written by an older build
/// therefore loads instead of throwing, and new fields simply take defaults.
public struct RoutineData: Codable, Sendable {
    /// 1 = the first schema that carried a version number. A file with no
    /// `schemaVersion` key at all is treated as version 0 and migrated.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var tasks: [RoutineTask]
    /// Keyed by yyyy-MM-dd.
    public var days: [String: DayRecord]
    public var settings: RoutineSettings

    public init(schemaVersion: Int = RoutineData.currentSchemaVersion,
                tasks: [RoutineTask],
                days: [String: DayRecord] = [:],
                settings: RoutineSettings) {
        self.schemaVersion = schemaVersion
        self.tasks = tasks
        self.days = days
        self.settings = settings
    }

    public static func makeDefault(startDateKey: String) -> RoutineData {
        RoutineData(tasks: DefaultRoutine.tasks(),
                    days: [:],
                    settings: RoutineSettings(startDateKey: startDateKey))
    }

    // MARK: - Decoding / migration

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        tasks = try c.decodeIfPresent([RoutineTask].self, forKey: .tasks) ?? []
        settings = try c.decodeIfPresent(RoutineSettings.self, forKey: .settings)
            ?? RoutineSettings(startDateKey: "")

        var decodedDays = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
        // Days may have been stored as an array in a very old file.
        if decodedDays.isEmpty, let list = try? c.decodeIfPresent([DayRecord].self, forKey: .days) {
            for day in list where !day.dateKey.isEmpty {
                decodedDays[day.dateKey] = day
            }
        }
        // v0 kept prayer times in their own top-level map.
        if let legacy = try? c.decodeIfPresent([String: PrayerTimes].self, forKey: .prayerTimes) {
            for (key, times) in legacy {
                var record = decodedDays[key] ?? DayRecord(dateKey: key)
                if record.prayerTimes == nil { record.prayerTimes = times }
                decodedDays[key] = record
            }
        }
        if let legacyOut = try? c.decodeIfPresent([String: Bool].self, forKey: .goingOut) {
            for (key, value) in legacyOut {
                var record = decodedDays[key] ?? DayRecord(dateKey: key)
                record.goingOut = value
                decodedDays[key] = record
            }
        }
        // A record whose dateKey was implied by its dictionary key.
        for (key, record) in decodedDays where record.dateKey.isEmpty {
            var fixed = record
            fixed.dateKey = key
            decodedDays[key] = fixed
        }
        days = decodedDays

        migrateInPlace()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(RoutineData.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(days, forKey: .days)
        try c.encode(settings, forKey: .settings)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, tasks, days, settings
        // Legacy top-level keys, read-only:
        case prayerTimes, goingOut
    }

    /// Brings any decoded document up to the current schema. Safe to run twice.
    public mutating func migrateInPlace(today: String? = nil) {
        if settings.startDateKey.isEmpty {
            settings.startDateKey = days.keys.min() ?? today ?? DateKey.today()
        }
        if tasks.isEmpty {
            tasks = DefaultRoutine.tasks()
        }
        ensureProtectedPrayers()

        // A v0 file had no wake-time setting, but it did have a Wake up task.
        // Adopt that task's time rather than overwriting it with the default.
        if schemaVersion < 1,
           let wake = tasks.first(where: { $0.id == DefaultTaskID.wake }),
           let time = wake.timing.fixedTime {
            settings.wakeTime = time
        }
        applyWakeTimeToWakeTask()

        // Re-anchor any sleep log that a v0 file only stored as a duration.
        // Such a log was parked on 04:50 by DayRecord's decoder; if the real
        // wake time differs, move it while keeping the duration intact.
        if schemaVersion < 1 {
            let parked = TimeOfDay(hour: 4, minute: 50)
            for (key, record) in days {
                guard let log = record.sleep,
                      log.wakeTime == parked,
                      log.wakeTime != settings.wakeTime else { continue }
                var updated = record
                updated.sleep = SleepMath.log(endingAt: settings.wakeTime,
                                              lastingMinutes: log.durationMinutes)
                days[key] = updated
            }
        }
        schemaVersion = RoutineData.currentSchemaVersion
    }

    // MARK: - Invariants

    /// Guarantees all five obligatory prayers exist, enabled, audible and
    /// correctly anchored. Called on load and after any reset.
    public mutating func ensureProtectedPrayers() {
        tasks = tasks.map { $0.normalised }
        for template in DefaultRoutine.prayerTasks() {
            guard let prayer = template.protectedPrayer else { continue }
            if let index = tasks.firstIndex(where: { $0.protectedPrayer == prayer }) {
                tasks[index] = tasks[index].normalised
            } else if let index = tasks.firstIndex(where: { $0.id == template.id }) {
                // Present but had lost its protected marker.
                var recovered = tasks[index]
                recovered.protectedPrayer = prayer
                tasks[index] = recovered.normalised
            } else {
                tasks.append(template)
            }
        }
    }

    /// The wake time setting is the single source of truth for the Wake task.
    public mutating func applyWakeTimeToWakeTask() {
        guard let index = tasks.firstIndex(where: { $0.id == DefaultTaskID.wake }) else { return }
        tasks[index].timing = .fixed(settings.wakeTime)
    }

    /// Reset to the shipped routine. Always recreates all five prayers.
    public mutating func resetTasksToDefaults() {
        tasks = DefaultRoutine.tasks()
        ensureProtectedPrayers()
        applyWakeTimeToWakeTask()
    }

    // MARK: - Day access

    public func day(_ key: String) -> DayRecord? { days[key] }

    public func prayerTimes(on key: String) -> PrayerTimes? {
        days[key]?.prayerTimes
    }

    public func isGoingOut(on key: String) -> Bool {
        days[key]?.goingOut ?? false
    }

    @discardableResult
    public mutating func mutateDay(_ key: String, _ body: (inout DayRecord) -> Void) -> DayRecord {
        var record = days[key] ?? DayRecord(dateKey: key)
        body(&record)
        record.dateKey = key
        days[key] = record
        return record
    }

    /// Persist validated times for one date. Returns the saved times.
    @discardableResult
    public mutating func savePrayerTimes(_ times: PrayerTimes, on key: String)
        -> Result<PrayerTimes, PrayerTimesValidationError> {
        switch PrayerTimesValidator.validate(times) {
        case .failure(let error):
            return .failure(error)
        case .success(let valid):
            mutateDay(key) { $0.prayerTimes = valid }
            return .success(valid)
        }
    }

    public mutating func setGoingOut(_ value: Bool, on key: String) {
        mutateDay(key) { $0.goingOut = value }
    }

    // MARK: - Task access

    public func task(_ id: UUID) -> RoutineTask? {
        tasks.first { $0.id == id }
    }

    /// Applies an edit, refusing anything the protected-prayer rules forbid.
    @discardableResult
    public mutating func updateTask(_ updated: RoutineTask, confirmed: Bool = false) -> TaskEditGuard {
        guard let index = tasks.firstIndex(where: { $0.id == updated.id }) else { return .allowed }
        let existing = tasks[index]
        if !updated.enabled, existing.enabled {
            let guardResult = TaskRules.canDisable(existing)
            switch guardResult {
            case .refused: return guardResult
            case .needsConfirmation where !confirmed: return guardResult
            default: break
            }
        }
        if !updated.alarm, existing.alarm {
            let guardResult = TaskRules.canMuteAlarm(existing)
            if case .refused = guardResult { return guardResult }
        }
        tasks[index] = updated.normalised
        if updated.id == DefaultTaskID.wake, let time = updated.timing.fixedTime {
            settings.wakeTime = time
        }
        return .allowed
    }

    /// Deletes unless the rules refuse. A preparation task returns
    /// `.needsConfirmation` and is NOT deleted until `confirmed` is passed.
    @discardableResult
    public mutating func deleteTask(_ id: UUID, confirmed: Bool = false) -> TaskEditGuard {
        guard let task = task(id) else { return .allowed }
        let guardResult = TaskRules.canDelete(task)
        switch guardResult {
        case .refused:
            return guardResult
        case .needsConfirmation where !confirmed:
            return guardResult
        default:
            tasks.removeAll { $0.id == id }
            return .allowed
        }
    }
}
