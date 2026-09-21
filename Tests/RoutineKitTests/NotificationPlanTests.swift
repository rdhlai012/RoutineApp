import XCTest
@testable import RoutineKit

final class NotificationPlanTests: XCTestCase {

    private var midnight: Date { TestSupport.startOfDay(TestSupport.dayKey) }

    // MARK: Identifiers

    func testIdentifierFormats() {
        let task = UUID(uuidString: "40B99FA1-53FC-4D71-8B1A-9F7B71D65128")!
        XCTAssertEqual(NotificationID.dated(task: task, dateKey: "2026-09-22", burst: 0),
                       "routine.40B99FA1-53FC-4D71-8B1A-9F7B71D65128.2026-09-22.0")
        XCTAssertEqual(NotificationID.daily(task: task, burst: 3),
                       "routine.40B99FA1-53FC-4D71-8B1A-9F7B71D65128.daily.3")
        XCTAssertEqual(NotificationID.nudge(dateKey: "2026-09-21"), "routine.nudge.2026-09-21")
    }

    func testIdentifierParsing() {
        let id = NotificationID.dated(task: DefaultTaskID.wake, dateKey: "2026-09-22", burst: 2)
        XCTAssertEqual(NotificationID.taskID(in: id), DefaultTaskID.wake)
        XCTAssertEqual(NotificationID.dateKey(in: id), "2026-09-22")
        XCTAssertFalse(NotificationID.isDaily(id))

        let daily = NotificationID.daily(task: DefaultTaskID.wake, burst: 0)
        XCTAssertTrue(NotificationID.isDaily(daily))
        XCTAssertNil(NotificationID.dateKey(in: daily))

        let nudge = NotificationID.nudge(dateKey: "2026-09-21")
        XCTAssertTrue(NotificationID.isNudge(nudge))
        XCTAssertEqual(NotificationID.dateKey(in: nudge), "2026-09-21")
    }

    func testSameInputProducesTheSameIdentifiersWithNoDuplicates() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        data.setGoingOut(true, on: TestSupport.dayKey)

        let first = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                              calendar: TestSupport.calendar, now: midnight)
        let second = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                               calendar: TestSupport.calendar, now: midnight)

        XCTAssertEqual(first.map(\.identifier), second.map(\.identifier))
        XCTAssertEqual(Set(first.map(\.identifier)).count, first.count, "identifiers must be unique")

        // Re-saving twice must not double anything up.
        let combined = Planner.deduplicate(first + second)
        XCTAssertEqual(combined.count, first.count)
    }

    func testInsistentWakeGetsFiveBurstsOneMinuteApart() {
        let data = TestSupport.data()
        let daily = Planner.dailyNotifications(data: data, calendar: TestSupport.calendar, now: midnight)
        let wake = daily.filter { $0.taskID == DefaultTaskID.wake }
            .sorted { $0.burstIndex < $1.burstIndex }

        XCTAssertEqual(wake.count, 5)
        XCTAssertEqual(wake.map(\.sound), Array(repeating: NotificationSound.alarmFile, count: 5))
        for (index, item) in wake.enumerated() {
            XCTAssertEqual(item.dateComponents.hour, 4)
            XCTAssertEqual(item.dateComponents.minute, 50 + index)
            XCTAssertTrue(item.repeatsDaily)
        }
    }

    func testAlarmOffMeansSilent() {
        var data = TestSupport.data()
        var dinner = data.task(DefaultTaskID.dinner)!
        dinner.alarm = false
        data.updateTask(dinner)

        let daily = Planner.dailyNotifications(data: data, calendar: TestSupport.calendar, now: midnight)
        XCTAssertEqual(daily.first { $0.taskID == DefaultTaskID.dinner }?.sound, .silent)
    }

    func testNoteAppearsInTheNotificationBody() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        data.setGoingOut(true, on: TestSupport.dayKey)
        let items = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                              calendar: TestSupport.calendar, now: midnight)
        let sunscreen = items.first { $0.taskID == DefaultTaskID.sunscreenAsr }
        XCTAssertNotNil(sunscreen)
        XCTAssertTrue(sunscreen!.body.contains("Skin1004 SPF 50"))
    }

    // MARK: Scoped removal

    func testScopedRemovalTouchesOnlyRoutineIdentifiers() {
        let foreign = ["com.apple.reminder.1", "whatsapp.message", "routineXX.not-ours", "myapp.routine.fake"]
        let ours = [
            NotificationID.dated(task: DefaultTaskID.fajrPrayer, dateKey: "2026-09-22", burst: 0),
            NotificationID.dated(task: DefaultTaskID.ishaPrayer, dateKey: "2026-09-22", burst: 0),
            NotificationID.dated(task: DefaultTaskID.fajrPrayer, dateKey: "2026-09-23", burst: 0),
            NotificationID.daily(task: DefaultTaskID.wake, burst: 0),
            NotificationID.nudge(dateKey: "2026-09-22")
        ]
        let all = foreign + ours

        let forDate = NotificationID.matching(all, dateKey: "2026-09-22")
        XCTAssertEqual(Set(forDate), Set([ours[0], ours[1], ours[4]]))
        for identifier in forDate {
            XCTAssertTrue(identifier.hasPrefix("routine."))
        }

        let tasksOnly = NotificationID.matchingTasks(all, dateKey: "2026-09-22")
        XCTAssertEqual(Set(tasksOnly), Set([ours[0], ours[1]]))
        XCTAssertFalse(tasksOnly.contains(NotificationID.nudge(dateKey: "2026-09-22")))

        let perTask = NotificationID.matching(all, task: DefaultTaskID.fajrPrayer)
        XCTAssertEqual(Set(perTask), Set([ours[0], ours[2]]))

        XCTAssertEqual(NotificationID.matchingDaily(all), [ours[3]])

        // Nothing foreign is ever selected.
        for identifier in foreign {
            XCTAssertFalse(NotificationID.isRoutine(identifier) && identifier.hasPrefix("routine."),
                           "\(identifier) must not be treated as ours")
        }
    }

    // MARK: The 60 cap

    func testCapKeepsTheSoonestSixty() {
        var data = TestSupport.data()
        for offset in 0...6 {
            let key = DateKey.offset(TestSupport.dayKey, byDays: offset, calendar: TestSupport.calendar)!
            data.mutateDay(key) { $0.prayerTimes = TestSupport.times() }
            data.setGoingOut(true, on: key)
        }
        let all = Planner.fullSchedule(data: data, calendar: TestSupport.calendar,
                                       now: midnight, horizonDays: 6)
        XCTAssertGreaterThan(all.count, Planner.pendingLimit)

        let capped = Planner.cap(all)
        XCTAssertEqual(capped.kept.count, Planner.pendingLimit)
        XCTAssertEqual(capped.truncated, all.count - Planner.pendingLimit)
        XCTAssertTrue(capped.didTruncate)

        // Kept items are the earliest ones, in order.
        let keptDates = capped.kept.compactMap(\.nextFireDate)
        XCTAssertEqual(keptDates, keptDates.sorted())
        let droppedEarliest = Set(all.map(\.identifier)).subtracting(capped.kept.map(\.identifier))
        for item in all where droppedEarliest.contains(item.identifier) {
            XCTAssertGreaterThanOrEqual(item.nextFireDate ?? .distantFuture,
                                        keptDates.last ?? .distantPast)
        }
    }

    func testCapIsANoOpBelowTheLimit() {
        let data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let items = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                              calendar: TestSupport.calendar, now: midnight)
        let capped = Planner.cap(items)
        XCTAssertEqual(capped.truncated, 0)
        XCTAssertEqual(capped.kept.count, items.count)
    }

    // MARK: Whole-date scheduling

    func testAllFivePrayersAreScheduledForADateWithExactTimes() {
        let data = TestSupport.data(withTimesOn: [TestSupport.nextKey])
        let items = Planner.dateNotifications(dateKey: TestSupport.nextKey, data: data,
                                              calendar: TestSupport.calendar,
                                              now: TestSupport.startOfDay(TestSupport.dayKey))
        let identifiers = items.map(\.identifier)
        let outcome = TomorrowSetup.verify(pendingIdentifiers: identifiers,
                                           dateKey: TestSupport.nextKey,
                                           data: data)
        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(outcome.prayersScheduled, Prayer.allCases)
        XCTAssertTrue(outcome.prayersMissing.isEmpty)
        XCTAssertEqual(outcome.pendingCount, identifiers.count)
        XCTAssertTrue(outcome.message(label: "Tomorrow").contains("Fajr, Dhuhr, Asr, Maghrib, Isha"))
    }

    func testReadBackReportsAnErrorWhenAPrayerIsMissing() {
        let data = TestSupport.data(withTimesOn: [TestSupport.nextKey])
        var identifiers = Planner.dateNotifications(dateKey: TestSupport.nextKey, data: data,
                                                    calendar: TestSupport.calendar,
                                                    now: TestSupport.startOfDay(TestSupport.dayKey))
            .map(\.identifier)
        let ishaID = NotificationID.dated(task: DefaultTaskID.ishaPrayer,
                                          dateKey: TestSupport.nextKey, burst: 0)
        identifiers.removeAll { $0 == ishaID }

        let outcome = TomorrowSetup.verify(pendingIdentifiers: identifiers,
                                           dateKey: TestSupport.nextKey, data: data)
        XCTAssertFalse(outcome.isSuccess)
        XCTAssertEqual(outcome.prayersMissing, [.isha])
        let message = outcome.message(label: "Tomorrow")
        XCTAssertTrue(message.contains("NOT fully scheduled"))
        XCTAssertFalse(message.contains("✓"))
    }

    func testPastMomentsAreNotScheduled() {
        let data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let noon = TestSupport.calendar.date(forKey: TestSupport.dayKey,
                                             at: TimeOfDay(hour: 12, minute: 0))!
        let items = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                              calendar: TestSupport.calendar, now: noon)
        XCTAssertFalse(items.contains { $0.taskID == DefaultTaskID.fajrPrayer })
        XCTAssertTrue(items.contains { $0.taskID == DefaultTaskID.maghribPrayer })
    }

    // MARK: Evening nudge

    func testNudgeIsFifteenMinutesAfterMaghrib() {
        let data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let nudge = Planner.nudgeNotification(dateKey: TestSupport.dayKey, data: data,
                                              calendar: TestSupport.calendar, now: midnight)
        XCTAssertNotNil(nudge)
        XCTAssertEqual(nudge?.identifier, NotificationID.nudge(dateKey: TestSupport.dayKey))
        XCTAssertEqual(nudge?.dateComponents.hour, 18)
        XCTAssertEqual(nudge?.dateComponents.minute, 39)     // Maghrib 18:24 + 15
    }

    func testNudgeDisappearsOnceTomorrowIsSaved() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        XCTAssertNotNil(Planner.nudgeNotification(dateKey: TestSupport.dayKey, data: data,
                                                  calendar: TestSupport.calendar, now: midnight))
        data.mutateDay(TestSupport.nextKey) { $0.prayerTimes = TestSupport.times() }
        XCTAssertNil(Planner.nudgeNotification(dateKey: TestSupport.dayKey, data: data,
                                               calendar: TestSupport.calendar, now: midnight),
                     "Saving tomorrow's times must cancel the nudge")
    }

    func testNoNudgeWithoutTodaysMaghrib() {
        let data = TestSupport.data()
        XCTAssertNil(Planner.nudgeNotification(dateKey: TestSupport.dayKey, data: data,
                                               calendar: TestSupport.calendar, now: midnight))
    }
}
