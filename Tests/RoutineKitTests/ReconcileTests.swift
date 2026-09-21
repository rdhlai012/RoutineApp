import XCTest
@testable import RoutineKit

final class ReconcileTests: XCTestCase {

    private var midnight: Date { TestSupport.startOfDay(TestSupport.dayKey) }

    func testForeignNotificationsAreNeverRemoved() {
        let foreign = ["com.apple.calendar.event", "some.other.app", "routineish.thing"]
        let data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let desired = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                                calendar: TestSupport.calendar, now: midnight)
        let stalePending = [NotificationID.dated(task: DefaultTaskID.fajrPrayer,
                                                 dateKey: "2026-01-01", burst: 0)]

        let plan = Planner.reconcile(pending: foreign + stalePending + desired.map(\.identifier),
                                     desired: desired)

        XCTAssertEqual(plan.toRemove, stalePending)
        for identifier in foreign {
            XCTAssertFalse(plan.toRemove.contains(identifier))
        }
    }

    func testTestAlarmIsPreserved() {
        let data = TestSupport.data()
        let desired = Planner.dailyNotifications(data: data, calendar: TestSupport.calendar,
                                                 now: midnight)
        let plan = Planner.reconcile(pending: [NotificationID.test], desired: desired)
        XCTAssertFalse(plan.toRemove.contains(NotificationID.test))
    }

    func testRunningTwiceWithTheSameInputChangesNothing() {
        let data = TestSupport.data(withTimesOn: [TestSupport.nextKey])
        let desired = Planner.dateNotifications(dateKey: TestSupport.nextKey, data: data,
                                                calendar: TestSupport.calendar, now: midnight)

        let first = Planner.reconcile(pending: [], desired: desired)
        let pendingAfterFirst = first.toAdd.map(\.identifier)
        let second = Planner.reconcile(pending: pendingAfterFirst, desired: desired)

        XCTAssertTrue(second.toRemove.isEmpty, "a repeat save must remove nothing")
        XCTAssertEqual(Set(second.toAdd.map(\.identifier)), Set(pendingAfterFirst))
        XCTAssertEqual(Set(pendingAfterFirst).count, pendingAfterFirst.count, "no duplicates")
    }

    func testResavingADateReplacesThatDateOnly() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey, TestSupport.nextKey])
        let todayIDs = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                                 calendar: TestSupport.calendar, now: midnight)
            .map(\.identifier)

        // Tomorrow's Isha moves; today's requests must be untouched.
        var times = TestSupport.times()
        times.isha = TimeOfDay(hour: 20, minute: 10)
        data.mutateDay(TestSupport.nextKey) { $0.prayerTimes = times }

        let pending = todayIDs + Planner.dateNotifications(dateKey: TestSupport.nextKey,
                                                           data: TestSupport.data(withTimesOn: [TestSupport.nextKey]),
                                                           calendar: TestSupport.calendar,
                                                           now: midnight).map(\.identifier)
        let desiredTomorrow = Planner.dateNotifications(dateKey: TestSupport.nextKey, data: data,
                                                        calendar: TestSupport.calendar, now: midnight)

        let scoped = NotificationID.matchingTasks(pending, dateKey: TestSupport.nextKey)
        let remaining = pending.filter { !scoped.contains($0) }
        let after = Set(remaining + desiredTomorrow.map(\.identifier))

        for identifier in todayIDs {
            XCTAssertTrue(after.contains(identifier), "today's reminder \(identifier) was lost")
        }
        XCTAssertEqual(after.count, Set(after).count)
    }

    func testDisablingATaskRemovesItsRequests() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let before = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                               calendar: TestSupport.calendar, now: midnight)
        var quran = data.task(DefaultTaskID.maghribQuran)!
        quran.enabled = false
        data.updateTask(quran)

        let after = Planner.dateNotifications(dateKey: TestSupport.dayKey, data: data,
                                              calendar: TestSupport.calendar, now: midnight)
        let plan = Planner.reconcile(pending: before.map(\.identifier), desired: after)

        XCTAssertEqual(plan.toRemove,
                       [NotificationID.dated(task: DefaultTaskID.maghribQuran,
                                             dateKey: TestSupport.dayKey, burst: 0)])
    }
}
