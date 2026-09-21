import Foundation
import UserNotifications

/// The one and only place that talks to UNUserNotificationCenter.
///
/// It makes no scheduling decisions: `Planner` (Foundation-only, unit tested)
/// decides what should exist, and this type applies that plan and reads back
/// what really happened. It NEVER calls removeAllPendingNotificationRequests().
@MainActor
final class NotificationScheduler: ObservableObject {
    static let shared = NotificationScheduler()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var lastTruncatedCount: Int = 0

    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current

    private init() {}

    var isDenied: Bool { authorizationStatus == .denied }

    var authorizationDescription: String {
        switch authorizationStatus {
        case .authorized: return "Allowed"
        case .provisional: return "Quiet delivery only"
        case .ephemeral: return "Temporary"
        case .denied: return "Blocked"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Permission

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    // MARK: - Reading back

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    private func refreshPendingCount() async {
        pendingCount = await center.pendingNotificationRequests()
            .filter { NotificationID.isRoutine($0.identifier) }
            .count
    }

    // MARK: - Applying a plan

    private func request(for planned: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        switch planned.sound {
        case .silent:
            content.sound = nil
        case .standard:
            content.sound = .default
        case .alarmFile:
            content.sound = UNNotificationSound(
                named: UNNotificationSoundName(NotificationSound.alarmFileName))
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: planned.dateComponents,
                                                    repeats: planned.repeatsDaily)
        return UNNotificationRequest(identifier: planned.identifier,
                                     content: content,
                                     trigger: trigger)
    }

    private func add(_ planned: [PlannedNotification]) async {
        for item in planned {
            do {
                try await center.add(request(for: item))
            } catch {
                #if DEBUG
                print("[Routine] could not schedule \(item.identifier): \(error)")
                #endif
            }
        }
    }

    /// Scoped removal: fetch what is pending, keep only our own identifiers,
    /// and remove just those. Anything belonging to another app or to iOS
    /// itself is never in the list we hand back to the system.
    private func remove(_ identifiers: [String]) {
        let ours = identifiers.filter { NotificationID.isRoutine($0) && !NotificationID.isTest($0) }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    // MARK: - Entry points

    /// Full reconcile. Used at launch, on foreground, and after any edit that
    /// can move more than one date (task edits, settings, reset).
    @discardableResult
    func reschedule(data: RoutineData, now: Date = Date()) async -> Int {
        let desired = Planner.fullSchedule(data: data, calendar: calendar, now: now)
        let capped = Planner.cap(desired)
        lastTruncatedCount = capped.truncated
        if capped.didTruncate {
            #if DEBUG
            print("[Routine] pending limit reached: kept \(capped.kept.count), "
                  + "skipped \(capped.truncated) later reminders")
            #endif
        }

        let pending = await pendingIdentifiers()
        let plan = Planner.reconcile(pending: pending, desired: capped.kept)
        remove(plan.toRemove)
        await add(plan.toAdd)
        await refreshPendingCount()
        return capped.kept.count
    }

    /// One date only: removes exactly that date's task requests, adds the new
    /// ones, then reads back what is genuinely pending for it.
    @discardableResult
    func rescheduleDate(_ dateKey: String, data: RoutineData, now: Date = Date()) async -> ScheduleOutcome {
        let pending = await pendingIdentifiers()
        remove(NotificationID.matchingTasks(pending, dateKey: dateKey))

        let desired = Planner.dateNotifications(dateKey: dateKey, data: data,
                                                calendar: calendar, now: now)
        // Budget the date against our OWN other pending requests. Notifications
        // belonging to other apps are not ours to count or to touch.
        let others = pending.filter {
            NotificationID.isRoutine($0) && NotificationID.dateKey(in: $0) != dateKey
        }.count
        let budget = max(0, Planner.pendingLimit - others)
        let capped = Planner.cap(desired, limit: budget)
        lastTruncatedCount = capped.truncated
        await add(capped.kept)

        // The nudge for the day before is no longer needed once this date is set.
        if let previous = DateKey.offset(dateKey, byDays: -1, calendar: calendar) {
            center.removePendingNotificationRequests(
                withIdentifiers: [NotificationID.nudge(dateKey: previous)])
        }

        let readBack = await pendingIdentifiers()
        await refreshPendingCount()
        return TomorrowSetup.verify(pendingIdentifiers: readBack,
                                    dateKey: dateKey,
                                    data: data,
                                    truncated: capped.truncated,
                                    savedAt: TimeOfDay(minutes: calendar.component(.hour, from: now) * 60
                                                       + calendar.component(.minute, from: now)))
    }

    /// Removes every routine request for one date (used when a day is cleared).
    func clearDate(_ dateKey: String) async {
        let pending = await pendingIdentifiers()
        remove(NotificationID.matching(pending, dateKey: dateKey))
        await refreshPendingCount()
    }

    // MARK: - Test alarm

    /// Fires the real alarm sound in 10 seconds so the volume and Silent-switch
    /// behaviour can be checked on the device.
    func sendTestAlarm(after seconds: TimeInterval = 10) async {
        let content = UNMutableNotificationContent()
        content.title = "Test alarm"
        content.body = "This is exactly how your wake-up alarm will sound."
        content.sound = UNNotificationSound(
            named: UNNotificationSoundName(NotificationSound.alarmFileName))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.test,
                                            content: content,
                                            trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.test])
        try? await center.add(request)
    }
}
