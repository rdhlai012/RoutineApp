import XCTest
@testable import RoutineKit

final class SleepAndStatsTests: XCTestCase {

    // MARK: Sleep

    func testCrossMidnightDuration() {
        let log = SleepLog(bedtime: TimeOfDay(hour: 22, minute: 10),
                           wakeTime: TimeOfDay(hour: 4, minute: 50))
        XCTAssertEqual(log.durationMinutes, 400)
        XCTAssertEqual(log.durationDescription, "6h 40m")
    }

    func testSameDayDuration() {
        let log = SleepLog(bedtime: TimeOfDay(hour: 1, minute: 0),
                           wakeTime: TimeOfDay(hour: 6, minute: 30))
        XCTAssertEqual(log.durationMinutes, 330)
    }

    func testTargetAndLatestBedtime() {
        let settings = RoutineSettings(startDateKey: TestSupport.startKey)
        XCTAssertEqual(settings.wakeTime, TimeOfDay(hour: 4, minute: 50))
        XCTAssertEqual(settings.targetBedtime, TimeOfDay(hour: 21, minute: 50))   // wake - 7h
        XCTAssertEqual(settings.latestBedtime, TimeOfDay(hour: 22, minute: 50))   // wake - 6h
    }

    func testSleepStatusBands() {
        let settings = RoutineSettings(startDateKey: TestSupport.startKey)
        XCTAssertEqual(SleepMath.status(SleepLog(bedtime: TimeOfDay(hour: 23, minute: 30),
                                                 wakeTime: TimeOfDay(hour: 4, minute: 50)),
                                        settings: settings), .belowMinimum)      // 5h20
        XCTAssertEqual(SleepMath.status(SleepLog(bedtime: TimeOfDay(hour: 22, minute: 10),
                                                 wakeTime: TimeOfDay(hour: 4, minute: 50)),
                                        settings: settings), .meetsMinimum)      // 6h40
        XCTAssertEqual(SleepMath.status(SleepLog(bedtime: TimeOfDay(hour: 21, minute: 40),
                                                 wakeTime: TimeOfDay(hour: 4, minute: 50)),
                                        settings: settings), .meetsGoal)         // 7h10
    }

    func testSevenDaySummary() {
        let settings = RoutineSettings(startDateKey: TestSupport.startKey)
        let logs = [
            SleepMath.log(endingAt: settings.wakeTime, lastingMinutes: 300),   // below
            SleepMath.log(endingAt: settings.wakeTime, lastingMinutes: 400),   // minimum
            SleepMath.log(endingAt: settings.wakeTime, lastingMinutes: 440)    // goal
        ]
        let summary = SleepMath.summarise(logs, settings: settings)
        XCTAssertEqual(summary.nightsLogged, 3)
        XCTAssertEqual(summary.averageMinutes, 380)
        XCTAssertEqual(summary.nightsMeetingMinimum, 2)
        XCTAssertEqual(summary.nightsMeetingGoal, 1)
    }

    func testWakeTimeIsSharedWithTheWakeTask() {
        var data = TestSupport.data()
        data.settings.wakeTime = TimeOfDay(hour: 5, minute: 15)
        data.applyWakeTimeToWakeTask()
        XCTAssertEqual(data.task(DefaultTaskID.wake)?.timing.fixedTime,
                       TimeOfDay(hour: 5, minute: 15))

        // ...and editing the task writes back to the setting.
        var wake = data.task(DefaultTaskID.wake)!
        wake.timing = .fixed(TimeOfDay(hour: 4, minute: 30))
        data.updateTask(wake)
        XCTAssertEqual(data.settings.wakeTime, TimeOfDay(hour: 4, minute: 30))
    }

    // MARK: Going out

    func testGoingOutIsPerDateAndDefaultsOff() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey, TestSupport.nextKey])
        data.setGoingOut(true, on: TestSupport.dayKey)

        XCTAssertTrue(data.isGoingOut(on: TestSupport.dayKey))
        XCTAssertFalse(data.isGoingOut(on: TestSupport.nextKey),
                       "Tomorrow must start OFF no matter what today is")
        XCTAssertFalse(data.isGoingOut(on: "2026-10-05"))
    }

    func testGoingOutAddsAndRemovesOnlyItsOwnTasks() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        let off = Planner.plan(dateKey: TestSupport.dayKey, data: data)
        XCTAssertNil(TestSupport.plannedTime(off, DefaultTaskID.sunscreenNoon))
        XCTAssertFalse(off.contains { $0.id == DefaultTaskID.sunscreenNoon })

        data.setGoingOut(true, on: TestSupport.dayKey)
        let on = Planner.plan(dateKey: TestSupport.dayKey, data: data)
        XCTAssertEqual(TestSupport.plannedTime(on, DefaultTaskID.sunscreenNoon),
                       TimeOfDay(hour: 12, minute: 0))
        XCTAssertEqual(TestSupport.plannedTime(on, DefaultTaskID.sunscreenAsr),
                       TimeOfDay(hour: 15, minute: 8))        // Asr 15:38 - 30

        XCTAssertEqual(on.count, off.count + 2)
        for item in off {
            XCTAssertEqual(TestSupport.plannedTime(on, item.id), item.time,
                           "\(item.task.title) must not move when going-out is toggled")
        }

        data.setGoingOut(false, on: TestSupport.dayKey)
        let backOff = Planner.plan(dateKey: TestSupport.dayKey, data: data)
        XCTAssertFalse(backOff.contains { $0.id == DefaultTaskID.sunscreenNoon })
    }

    func testGoingOutOnlyTasksAreNeverScheduledDaily() {
        var data = TestSupport.data()
        data.setGoingOut(true, on: TestSupport.dayKey)
        let daily = Planner.dailyNotifications(data: data,
                                               calendar: TestSupport.calendar,
                                               now: TestSupport.startOfDay(TestSupport.dayKey))
        XCTAssertFalse(daily.contains { $0.taskID == DefaultTaskID.sunscreenNoon },
                       "A going-out task is per-date, so it must never become a daily repeat")
    }

    // MARK: Stats

    /// Marks every resolved task on `key` complete, or `fraction` of them.
    private func fill(_ data: inout RoutineData, key: String, fraction: Double) {
        let planned = Planner.plan(dateKey: key, data: data).filter(\.isResolved)
        let take = Int((Double(planned.count) * fraction).rounded(.down))
        data.mutateDay(key) { $0.completedTaskIDs = Set(planned.prefix(take).map(\.id)) }
    }

    func testCompletionAndDayState() {
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        XCTAssertEqual(Stats.completion(dateKey: TestSupport.dayKey, data: data).state, .missed)

        fill(&data, key: TestSupport.dayKey, fraction: 0.5)
        XCTAssertEqual(Stats.completion(dateKey: TestSupport.dayKey, data: data).state, .partial)

        fill(&data, key: TestSupport.dayKey, fraction: 1.0)
        let done = Stats.completion(dateKey: TestSupport.dayKey, data: data)
        XCTAssertEqual(done.state, .complete)
        XCTAssertEqual(done.percent, 100)

        XCTAssertEqual(Stats.completion(dateKey: "2030-01-01",
                                        data: RoutineData(tasks: [],
                                                          settings: .init(startDateKey: "2030-01-01"))).state,
                       .noData)
    }

    func testDayNumber() {
        let data = TestSupport.data()
        XCTAssertEqual(Stats.dayNumber(on: TestSupport.startKey, data: data,
                                       calendar: TestSupport.calendar), 1)
        XCTAssertEqual(Stats.dayNumber(on: "2026-09-21", data: data,
                                       calendar: TestSupport.calendar), 21)
    }

    func testCurrentAndLongestStreak() {
        let start = "2026-09-01"
        var data = RoutineData.makeDefault(startDateKey: start)
        // Only fixed tasks resolve (no prayer times), which is enough to score.
        // Good: 1,2,3,4  bad: 5  good: 6,7  bad: 8  good: 9,10 (10 = "today")
        let goodDays = [1, 2, 3, 4, 6, 7, 9, 10]
        for offset in 0..<10 {
            let key = DateKey.offset(start, byDays: offset, calendar: TestSupport.calendar)!
            fill(&data, key: key, fraction: goodDays.contains(offset + 1) ? 1.0 : 0.1)
        }
        let today = DateKey.offset(start, byDays: 9, calendar: TestSupport.calendar)!

        XCTAssertEqual(Stats.longestStreak(upTo: today, data: data, calendar: TestSupport.calendar), 4)
        XCTAssertEqual(Stats.currentStreak(upTo: today, data: data, calendar: TestSupport.calendar), 2)

        let summary = Stats.summary(upTo: today, data: data, calendar: TestSupport.calendar)
        XCTAssertEqual(summary.goodDays, 8)
        XCTAssertEqual(summary.dayNumber, 10)
        XCTAssertEqual(summary.daysRecorded, 10)
    }

    func testTodayInProgressDoesNotBreakTheStreak() {
        let start = "2026-09-01"
        var data = RoutineData.makeDefault(startDateKey: start)
        for offset in 0..<4 {
            let key = DateKey.offset(start, byDays: offset, calendar: TestSupport.calendar)!
            fill(&data, key: key, fraction: 1.0)
        }
        // Day 5 has barely started.
        let today = DateKey.offset(start, byDays: 4, calendar: TestSupport.calendar)!
        fill(&data, key: today, fraction: 0.1)

        XCTAssertEqual(Stats.currentStreak(upTo: today, data: data, calendar: TestSupport.calendar), 4)
    }

    func testGoodDayThresholdIsConfigurable() {
        var data = TestSupport.data()
        let key = TestSupport.startKey
        fill(&data, key: key, fraction: 0.9)
        let completion = Stats.completion(dateKey: key, data: data)

        XCTAssertTrue(Stats.isGoodDay(completion, threshold: 0.8))
        XCTAssertFalse(Stats.isGoodDay(completion, threshold: 0.95))
    }
}
