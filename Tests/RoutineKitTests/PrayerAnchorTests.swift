import XCTest
@testable import RoutineKit

final class PrayerAnchorTests: XCTestCase {

    // MARK: No fallback, ever

    func testDateWithoutSavedTimesHasNoPrayerTimes() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        // Yesterday and tomorrow have times; the middle day does not.
        data.mutateDay("2026-09-19") { $0.prayerTimes = TestSupport.times() }
        data.mutateDay("2026-09-23") { $0.prayerTimes = TestSupport.times() }

        XCTAssertNil(data.prayerTimes(on: "2026-09-20"),
                     "A date with no saved times must never borrow another date's times")
    }

    func testAnchoredTasksAreUnresolvedAndUnscheduledWithoutTimes() {
        let data = TestSupport.data()   // no times anywhere
        let planned = Planner.plan(dateKey: TestSupport.dayKey, data: data)

        let anchored = planned.filter { $0.task.timing.isAnchored }
        XCTAssertFalse(anchored.isEmpty)
        for item in anchored {
            XCTAssertNil(item.time)
            XCTAssertEqual(item.unresolvedReason, "No prayer times")
        }

        let notifications = Planner.dateNotifications(dateKey: TestSupport.dayKey,
                                                      data: data,
                                                      calendar: TestSupport.calendar,
                                                      now: TestSupport.startOfDay(TestSupport.dayKey))
        XCTAssertTrue(notifications.isEmpty,
                      "Nothing may be scheduled for a date whose prayer times are unknown")
    }

    func testFixedTasksStillResolveWithoutPrayerTimes() {
        let data = TestSupport.data()
        let planned = Planner.plan(dateKey: TestSupport.dayKey, data: data)
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.wake),
                       TimeOfDay(hour: 4, minute: 50))
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.gym),
                       TimeOfDay(hour: 20, minute: 40))
    }

    // MARK: Offsets

    func testAnchorOffsetsBeforeAndAfter() {
        let data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let planned = Planner.plan(dateKey: TestSupport.dayKey, data: data)

        // Fajr 04:58
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.fajrWudu),
                       TimeOfDay(hour: 4, minute: 48))        // -10
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.fajrAdhan),
                       TimeOfDay(hour: 4, minute: 58))        // +0
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.fajrPrayer),
                       TimeOfDay(hour: 5, minute: 3))         // +5
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.fajrQuran),
                       TimeOfDay(hour: 5, minute: 13))        // +15
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.morningSkincare),
                       TimeOfDay(hour: 5, minute: 38))        // +40

        // Dhuhr 12:15
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.dhuhrBrush),
                       TimeOfDay(hour: 11, minute: 55))       // -20
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.dhuhrWudu),
                       TimeOfDay(hour: 12, minute: 5))        // -10
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.dhuhrPrayer),
                       TimeOfDay(hour: 12, minute: 15))       // +0

        // Maghrib 18:24 + 15
        XCTAssertEqual(TestSupport.plannedTime(planned, DefaultTaskID.maghribQuran),
                       TimeOfDay(hour: 18, minute: 39))
    }

    // MARK: Only anchored tasks move

    func testChangingAPrayerMovesOnlyItsAnchoredTasks() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let before = Planner.plan(dateKey: TestSupport.dayKey, data: data)

        // Fajr slips 12 minutes later; nothing else changes.
        var times = TestSupport.times()
        times.fajr = TimeOfDay(hour: 5, minute: 10)
        data.mutateDay(TestSupport.dayKey) { $0.prayerTimes = times }
        let after = Planner.plan(dateKey: TestSupport.dayKey, data: data)

        XCTAssertEqual(TestSupport.plannedTime(after, DefaultTaskID.fajrWudu),
                       TimeOfDay(hour: 5, minute: 0))
        XCTAssertEqual(TestSupport.plannedTime(after, DefaultTaskID.fajrPrayer),
                       TimeOfDay(hour: 5, minute: 15))

        for task in data.tasks where task.timing.anchorPrayer != .fajr {
            XCTAssertEqual(TestSupport.plannedTime(before, task.id),
                           TestSupport.plannedTime(after, task.id),
                           "\(task.title) must not move when only Fajr changes")
        }
    }

    func testChangingIshaMovesIshaWuduAndPrayerOnly() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let before = Planner.plan(dateKey: TestSupport.dayKey, data: data)

        var times = TestSupport.times()
        times.isha = TimeOfDay(hour: 20, minute: 5)      // was 19:35, +30
        data.mutateDay(TestSupport.dayKey) { $0.prayerTimes = times }
        let after = Planner.plan(dateKey: TestSupport.dayKey, data: data)

        XCTAssertEqual(TestSupport.plannedTime(after, DefaultTaskID.ishaBrush),
                       TimeOfDay(hour: 19, minute: 45))
        XCTAssertEqual(TestSupport.plannedTime(after, DefaultTaskID.ishaWudu),
                       TimeOfDay(hour: 19, minute: 55))
        XCTAssertEqual(TestSupport.plannedTime(after, DefaultTaskID.ishaPrayer),
                       TimeOfDay(hour: 20, minute: 5))

        let moved = Set([DefaultTaskID.ishaBrush, DefaultTaskID.ishaWudu, DefaultTaskID.ishaPrayer])
        for task in data.tasks where !moved.contains(task.id) {
            XCTAssertEqual(TestSupport.plannedTime(before, task.id),
                           TestSupport.plannedTime(after, task.id),
                           "\(task.title) must not move when only Isha changes")
        }
    }

    // MARK: The Fajr sequence

    func testFajrSequenceIsInOrder() {
        let data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let planned = Planner.plan(dateKey: TestSupport.dayKey, data: data)
        let expected = [
            DefaultTaskID.wake,            // 04:50
            DefaultTaskID.brushMorning,    // 04:55
            DefaultTaskID.bath,            // 05:00
            DefaultTaskID.fajrWudu,        // Fajr - 10  (needs Fajr late enough)
            DefaultTaskID.fajrAdhan,
            DefaultTaskID.fajrPrayer,
            DefaultTaskID.fajrQuran,
            DefaultTaskID.morningSkincare
        ]

        // Use a Fajr late enough that wudu genuinely follows the bath.
        var late = TestSupport.times()
        late.fajr = TimeOfDay(hour: 5, minute: 20)
        var shifted = data
        shifted.mutateDay(TestSupport.dayKey) { $0.prayerTimes = late }
        let order = Planner.plan(dateKey: TestSupport.dayKey, data: shifted)
            .compactMap { expected.contains($0.id) ? $0.id : nil }

        XCTAssertEqual(order, expected, "Wudu must fall between Bath and Fajr")

        // And the offsets themselves are in the right relative order.
        XCTAssertLessThan(TestSupport.plannedTime(planned, DefaultTaskID.fajrWudu)!,
                          TestSupport.plannedTime(planned, DefaultTaskID.fajrAdhan)!)
        XCTAssertLessThan(TestSupport.plannedTime(planned, DefaultTaskID.fajrAdhan)!,
                          TestSupport.plannedTime(planned, DefaultTaskID.fajrPrayer)!)
    }

    func testEarlyFajrIsFlaggedAsOutOfSequence() {
        var data = TestSupport.data()
        var times = TestSupport.times()
        times.fajr = TimeOfDay(hour: 4, minute: 58)       // wudu 04:48, before the 05:00 bath
        data.mutateDay(TestSupport.dayKey) { $0.prayerTimes = times }

        let conflicts = ConflictChecker.check(dateKey: TestSupport.dayKey, data: data)
        XCTAssertTrue(conflicts.contains { $0.kind == .outOfSequence && $0.message.contains("Bath") },
                      "Expected a Bath/Wudu sequence conflict, got: \(conflicts.map(\.message))")
    }

    func testIshaAfterGymIsFlagged() {
        var data = TestSupport.data()
        var times = TestSupport.times()
        times.isha = TimeOfDay(hour: 20, minute: 55)      // after the 20:40 gym slot
        data.mutateDay(TestSupport.dayKey) { $0.prayerTimes = times }

        let conflicts = ConflictChecker.check(dateKey: TestSupport.dayKey, data: data)
        XCTAssertTrue(conflicts.contains { $0.kind == .prayerAfterGym })
    }

    // MARK: Validation

    func testValidationRejectsOutOfOrderTimes() {
        var times = TestSupport.times()
        times.asr = TimeOfDay(hour: 11, minute: 0)        // before Dhuhr
        switch PrayerTimesValidator.validate(times) {
        case .success:
            XCTFail("Asr before Dhuhr must be rejected")
        case .failure(let error):
            XCTAssertEqual(error, .outOfOrder(earlier: .dhuhr, later: .asr))
        }
    }

    func testValidationRejectsEqualTimes() {
        var times = TestSupport.times()
        times.isha = times.maghrib
        if case .success = PrayerTimesValidator.validate(times) {
            XCTFail("Isha equal to Maghrib must be rejected")
        }
    }

    func testSavingRejectsBadTimesAndLeavesTheDayUntouched() {
        var data = TestSupport.data()
        var times = TestSupport.times()
        times.maghrib = TimeOfDay(hour: 6, minute: 0)     // before Asr
        let result = data.savePrayerTimes(times, on: TestSupport.dayKey)

        if case .success = result { XCTFail("Invalid times must not be saved") }
        XCTAssertNil(data.prayerTimes(on: TestSupport.dayKey))
    }
}
