import XCTest
@testable import RoutineKit

final class InsightTests: XCTestCase {

    private let cal = TestSupport.calendar

    /// Marks `count` of the day's resolved tasks complete.
    private func complete(_ data: inout RoutineData, key: String, count: Int) {
        let planned = Planner.plan(dateKey: key, data: data).filter(\.isResolved)
        data.mutateDay(key) { $0.completedTaskIDs = Set(planned.prefix(count).map(\.id)) }
    }

    func testMissingPrayerTimesTakesPriority() {
        var data = TestSupport.data()            // no times anywhere
        complete(&data, key: TestSupport.dayKey, count: 3)

        let insight = InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal)
        XCTAssertEqual(insight.kind, .noPrayerTimes)
        XCTAssertEqual(insight.headline, "Prayer times needed")
    }

    func testAheadOfYesterday() {
        let yesterday = "2026-09-20"
        var data = TestSupport.data(withTimesOn: [yesterday, TestSupport.dayKey])
        complete(&data, key: yesterday, count: 4)
        complete(&data, key: TestSupport.dayKey, count: 6)

        let insight = InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal)
        XCTAssertEqual(insight.kind, .ahead)
        XCTAssertEqual(insight.headline, "Ahead of yesterday")
        XCTAssertTrue(insight.detail.contains("6"))
        XCTAssertTrue(insight.detail.contains("4"))
    }

    func testLevelWithYesterday() {
        let yesterday = "2026-09-20"
        var data = TestSupport.data(withTimesOn: [yesterday, TestSupport.dayKey])
        complete(&data, key: yesterday, count: 5)
        complete(&data, key: TestSupport.dayKey, count: 5)

        XCTAssertEqual(InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal).kind,
                       .level)
    }

    func testBehindYesterdayCountsTheGapAndPluralises() {
        let yesterday = "2026-09-20"
        var data = TestSupport.data(withTimesOn: [yesterday, TestSupport.dayKey])
        complete(&data, key: yesterday, count: 6)
        complete(&data, key: TestSupport.dayKey, count: 5)

        let one = InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal)
        XCTAssertEqual(one.kind, .behind)
        XCTAssertTrue(one.detail.contains("1 task behind"), one.detail)

        complete(&data, key: TestSupport.dayKey, count: 3)
        let many = InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal)
        XCTAssertTrue(many.detail.contains("3 tasks behind"), many.detail)
    }

    func testAllDoneBeatsTheComparison() {
        let yesterday = "2026-09-20"
        var data = TestSupport.data(withTimesOn: [yesterday, TestSupport.dayKey])
        complete(&data, key: yesterday, count: 2)
        let all = Planner.plan(dateKey: TestSupport.dayKey, data: data).filter(\.isResolved).count
        complete(&data, key: TestSupport.dayKey, count: all)

        let insight = InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal)
        XCTAssertEqual(insight.kind, .allDone)
        XCTAssertTrue(insight.detail.contains("\(all)"))
    }

    func testYesterdayWithNothingPlannedReadsAsFirstDay() {
        // Only prayer-anchored tasks, so a day without times has nothing planned.
        var data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        data.tasks.removeAll { !$0.timing.isAnchored }

        let insight = InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal)
        XCTAssertEqual(insight.kind, .firstDay, "yesterday has no times, so nothing to compare")
        XCTAssertTrue(insight.detail.contains("to go today"), insight.detail)
    }

    func testAnUntouchedDayIsStillLevelRatherThanBehind() {
        let yesterday = "2026-09-20"
        let data = TestSupport.data(withTimesOn: [yesterday, TestSupport.dayKey])
        // Nothing done on either day.
        XCTAssertEqual(InsightEngine.insight(on: TestSupport.dayKey, data: data, calendar: cal).kind,
                       .level)
    }

    func testEverySymbolIsNonEmpty() {
        for kind in [DailyInsight.Kind.noPrayerTimes, .allDone, .ahead, .level, .behind, .firstDay] {
            let insight = DailyInsight(kind: kind, headline: "h", detail: "d")
            XCTAssertFalse(insight.symbolName.isEmpty)
        }
    }
}
