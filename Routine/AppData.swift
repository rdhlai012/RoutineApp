import Foundation
import SwiftUI

/// The app's single source of truth. Owns the document, saves it, and asks the
/// scheduler to re-apply the plan whenever something that affects timing changes.
@MainActor
final class AppData: ObservableObject {
    @Published private(set) var data: RoutineData
    @Published var lastOutcome: ScheduleOutcome?
    @Published var banner: String?

    private let storage: RoutineStorage
    private let scheduler = NotificationScheduler.shared
    private let calendar = Calendar.current

    init(storage: RoutineStorage = RoutineStorage(url: RoutineStorage.documentsURL())) {
        self.storage = storage
        try? storage.backupIfNeeded()
        self.data = storage.load()
        persist()
    }

    // MARK: - Dates

    var todayKey: String { DateKey.today(calendar) }
    var tomorrowKey: String { DateKey.tomorrow(calendar) }

    // MARK: - Persistence

    private func persist() {
        do {
            try storage.save(data)
        } catch {
            banner = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Mutate, save, and re-apply the whole notification plan.
    private func mutate(_ body: (inout RoutineData) -> Void) {
        body(&data)
        persist()
        Task { await scheduler.reschedule(data: data) }
    }

    // MARK: - Reading

    func day(_ key: String) -> DayRecord? { data.day(key) }
    func prayerTimes(on key: String) -> PrayerTimes? { data.prayerTimes(on: key) }
    func isGoingOut(on key: String) -> Bool { data.isGoingOut(on: key) }
    func plan(for key: String) -> [PlannedTask] { Planner.plan(dateKey: key, data: data) }
    func conflicts(for key: String) -> [ScheduleConflict] {
        ConflictChecker.check(dateKey: key, data: data)
    }
    func completion(for key: String) -> DayCompletion { Stats.completion(dateKey: key, data: data) }

    var settings: RoutineSettings { data.settings }
    var tasks: [RoutineTask] { data.tasks }

    var stats: RoutineStats { Stats.summary(upTo: todayKey, data: data, calendar: calendar) }

    var recentSleepSummary: SleepSummary {
        SleepMath.summarise(Stats.recentSleep(upTo: todayKey, data: data, calendar: calendar),
                            settings: data.settings)
    }

    var needsTodaysPrayerTimes: Bool { prayerTimes(on: todayKey) == nil }
    var needsTomorrowsPrayerTimes: Bool { prayerTimes(on: tomorrowKey) == nil }

    // MARK: - Prayer times

    /// Saves one date's times and reschedules just that date, then reports the
    /// real read-back from the notification centre.
    func savePrayerTimes(_ draft: PrayerTimesDraft, on key: String) async -> Result<ScheduleOutcome,
                                                                                    PrayerTimesValidationError> {
        // 1. validate
        let validated = TomorrowSetup.validate(draft)
        guard case .success(let times) = validated else {
            if case .failure(let error) = validated { return .failure(error) }
            return .failure(.missing(draft.missing))
        }

        // 2. persist
        data.mutateDay(key) { $0.prayerTimes = times }
        persist()

        // 3 + 4. scoped removal for this date, then schedule the new ones
        // 5. read back what is genuinely pending
        let outcome = await scheduler.rescheduleDate(key, data: data)
        lastOutcome = outcome

        // The nudge chain and any neighbouring day may now differ.
        await scheduler.reschedule(data: data)
        return .success(outcome)
    }

    func clearPrayerTimes(on key: String) {
        data.mutateDay(key) { $0.prayerTimes = nil }
        persist()
        Task {
            await scheduler.clearDate(key)
            await scheduler.reschedule(data: data)
        }
    }

    // MARK: - Going out

    func setGoingOut(_ value: Bool, on key: String) {
        data.setGoingOut(value, on: key)
        persist()
        Task {
            let outcome = await scheduler.rescheduleDate(key, data: data)
            lastOutcome = outcome
        }
    }

    // MARK: - Completion

    func toggleTask(_ id: UUID, on key: String) {
        data.mutateDay(key) { record in
            if record.completedTaskIDs.contains(id) {
                record.completedTaskIDs.remove(id)
            } else {
                record.completedTaskIDs.insert(id)
            }
        }
        persist()
    }

    func isComplete(_ id: UUID, on key: String) -> Bool {
        data.day(key)?.completedTaskIDs.contains(id) ?? false
    }

    func toggleStep(_ stepID: UUID, task: UUID, on key: String) {
        data.mutateDay(key) { record in
            var set = record.completedStepIDs[task] ?? []
            if set.contains(stepID) { set.remove(stepID) } else { set.insert(stepID) }
            record.completedStepIDs[task] = set
        }
        persist()
    }

    func isStepComplete(_ stepID: UUID, task: UUID, on key: String) -> Bool {
        data.day(key)?.completedStepIDs[task]?.contains(stepID) ?? false
    }

    // MARK: - Notes

    func setNote(_ text: String, on key: String) {
        data.mutateDay(key) { $0.note = text.isEmpty ? nil : text }
        persist()
    }

    // MARK: - Sleep

    func setSleep(bedtime: TimeOfDay, wakeTime: TimeOfDay, on key: String) {
        data.mutateDay(key) { $0.sleep = SleepLog(bedtime: bedtime, wakeTime: wakeTime) }
        persist()
    }

    func clearSleep(on key: String) {
        data.mutateDay(key) { $0.sleep = nil }
        persist()
    }

    func sleep(on key: String) -> SleepLog? { data.day(key)?.sleep }

    func sleepStatus(on key: String) -> SleepStatus? {
        guard let log = sleep(on: key) else { return nil }
        return SleepMath.status(log, settings: data.settings)
    }

    // MARK: - Tasks

    @discardableResult
    func update(_ task: RoutineTask, confirmed: Bool = false) -> TaskEditGuard {
        var copy = data
        let result = copy.updateTask(task, confirmed: confirmed)
        guard case .allowed = result else { return result }
        mutate { $0 = copy }
        return result
    }

    @discardableResult
    func delete(_ id: UUID, confirmed: Bool = false) -> TaskEditGuard {
        var copy = data
        let result = copy.deleteTask(id, confirmed: confirmed)
        guard case .allowed = result else { return result }
        mutate { $0 = copy }
        return result
    }

    func add(_ task: RoutineTask) {
        mutate { $0.tasks.append(task) }
    }

    func moveTasks(from offsets: IndexSet, to destination: Int) {
        mutate { $0.tasks.move(fromOffsets: offsets, toOffset: destination) }
    }

    func resetToDefaults() {
        mutate { $0.resetTasksToDefaults() }
        banner = "Routine reset. All five prayers restored."
    }

    // MARK: - Settings

    func updateSettings(_ newValue: RoutineSettings) {
        mutate {
            $0.settings = newValue
            $0.applyWakeTimeToWakeTask()
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        Task {
            await scheduler.refreshAuthorization()
            if scheduler.authorizationStatus == .notDetermined {
                await scheduler.requestAuthorization()
            }
            await scheduler.reschedule(data: data)
        }
    }

    func onForeground() {
        Task {
            await scheduler.refreshAuthorization()
            await scheduler.reschedule(data: data)
        }
    }
}
