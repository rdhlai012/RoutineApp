import XCTest
@testable import RoutineKit

final class MigrationTests: XCTestCase {

    private func loadOldFixture() throws -> RoutineData {
        let url = TestSupport.fixtureURL("old-routine.json")
        let raw = try Data(contentsOf: url)
        var data = try RoutineStorage.decode(raw)
        data.migrateInPlace(today: TestSupport.dayKey)
        return data
    }

    func testOldFileLoadsAndIsStamped() throws {
        let data = try loadOldFixture()
        XCTAssertEqual(data.schemaVersion, RoutineData.currentSchemaVersion)
        XCTAssertEqual(data.settings.startDateKey, "2026-09-01", "legacy startDate key is honoured")
    }

    func testLegacyPrayerTimesMapIsFoldedIntoTheDay() throws {
        let data = try loadOldFixture()
        let times = data.prayerTimes(on: "2026-09-01")
        XCTAssertNotNil(times)
        XCTAssertEqual(times?.fajr, TimeOfDay(hour: 4, minute: 58))
        XCTAssertEqual(times?.isha, TimeOfDay(hour: 19, minute: 35))

        // And a date that had none still has none - no fallback on migration either.
        XCTAssertNil(data.prayerTimes(on: "2026-09-02"))
    }

    func testLegacyGoingOutMapIsFoldedIn() throws {
        let data = try loadOldFixture()
        XCTAssertTrue(data.isGoingOut(on: "2026-09-01"))
        XCTAssertFalse(data.isGoingOut(on: "2026-09-02"))
    }

    func testLegacySleepHoursBecomesBedAndWakeTimes() throws {
        let data = try loadOldFixture()
        let sleep = data.day("2026-09-01")?.sleep
        XCTAssertEqual(sleep?.durationMinutes, 390)                          // 6.5 h
        XCTAssertEqual(sleep?.wakeTime, TimeOfDay(hour: 4, minute: 50))
        XCTAssertEqual(sleep?.bedtime, TimeOfDay(hour: 22, minute: 20))
    }

    func testLegacyTaskShapesAreUnderstood() throws {
        let data = try loadOldFixture()

        // "time": 290 -> fixed 04:50
        XCTAssertEqual(data.task(DefaultTaskID.wake)?.timing.fixedTime,
                       TimeOfDay(hour: 4, minute: 50))
        XCTAssertEqual(data.task(DefaultTaskID.wake)?.insistent, true)

        // "anchor" + "offsetMinutes" -> anchored
        XCTAssertEqual(data.task(DefaultTaskID.fajrWudu)?.timing,
                       TaskTiming.anchored(prayer: .fajr, offset: -10))
        XCTAssertEqual(data.task(DefaultTaskID.morningSkincare)?.timing,
                       TaskTiming.anchored(prayer: .fajr, offset: 40))

        // Steps survive, including their enabled flags; ids are generated.
        let steps = data.task(DefaultTaskID.morningSkincare)?.steps ?? []
        XCTAssertEqual(steps.map(\.name),
                       ["Round Lab Dokdo Cleanser", "Dr. Althea 345", "Skin1004 SPF 50"])
        XCTAssertEqual(steps.last?.enabled, false)

        // An unknown category is mapped rather than lost.
        XCTAssertEqual(data.task(DefaultTaskID.gym)?.category, .gym)
    }

    func testCompletionsSurvive() throws {
        let data = try loadOldFixture()
        XCTAssertTrue(data.day("2026-09-01")?.completedTaskIDs.contains(DefaultTaskID.wake) ?? false)
        XCTAssertEqual(data.day("2026-09-01")?.note, "felt good")
    }

    func testMigrationAddsTheMissingProtectedPrayers() throws {
        let data = try loadOldFixture()
        XCTAssertEqual(Set(data.tasks.compactMap(\.protectedPrayer)), Set(Prayer.allCases),
                       "an old file that never had prayer tasks gains all five")
    }

    func testMigrationIsIdempotent() throws {
        var once = try loadOldFixture()
        let encodedOnce = try RoutineStorage.makeEncoder().encode(once)

        once.migrateInPlace(today: TestSupport.dayKey)
        let encodedTwice = try RoutineStorage.makeEncoder().encode(once)
        XCTAssertEqual(encodedOnce, encodedTwice)

        // A full save/load cycle is stable too.
        var reloaded = try RoutineStorage.decode(encodedTwice)
        reloaded.migrateInPlace(today: TestSupport.dayKey)
        XCTAssertEqual(try RoutineStorage.makeEncoder().encode(reloaded), encodedTwice)
    }

    func testUnknownFieldsAreIgnoredAndMissingOnesDefault() throws {
        let json = """
        {
          "schemaVersion": 1,
          "somethingFromTheFuture": { "nested": true },
          "tasks": [
            { "title": "Only a title" }
          ],
          "days": { "2026-09-21": { "goingOut": true } }
        }
        """.data(using: .utf8)!

        var data = try RoutineStorage.decode(json)
        data.migrateInPlace(today: TestSupport.dayKey)

        let task = data.tasks.first { $0.title == "Only a title" }
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.enabled, true)
        XCTAssertEqual(task?.category, .other)
        XCTAssertTrue(data.isGoingOut(on: "2026-09-21"))
        XCTAssertEqual(data.settings.startDateKey, "2026-09-21")
        XCTAssertEqual(Set(data.tasks.compactMap(\.protectedPrayer)), Set(Prayer.allCases))
    }

    func testEmptyFileBecomesTheDefaultRoutine() throws {
        var data = try RoutineStorage.decode("{}".data(using: .utf8)!)
        data.migrateInPlace(today: TestSupport.dayKey)
        XCTAssertEqual(data.tasks.count, DefaultRoutine.tasks().count)
        // An empty file has no days to infer a start date from, so decoding
        // stamps the device's today. Assert it is a real key, not a fixed date,
        // or this test would start failing tomorrow.
        XCTAssertFalse(data.settings.startDateKey.isEmpty)
        XCTAssertTrue(DateKey.isValid(data.settings.startDateKey))
    }

    func testRoundTripThroughDisk() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("routine-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storage = RoutineStorage(url: tmp)
        var original = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        original.setGoingOut(true, on: TestSupport.dayKey)
        original.mutateDay(TestSupport.dayKey) {
            $0.sleep = SleepLog(bedtime: TimeOfDay(hour: 22, minute: 10),
                                wakeTime: TimeOfDay(hour: 4, minute: 50))
            $0.note = "long day"
        }
        try storage.save(original)

        let loaded = storage.load(today: TestSupport.dayKey)
        XCTAssertEqual(loaded.prayerTimes(on: TestSupport.dayKey), original.prayerTimes(on: TestSupport.dayKey))
        XCTAssertTrue(loaded.isGoingOut(on: TestSupport.dayKey))
        XCTAssertEqual(loaded.day(TestSupport.dayKey)?.sleep?.durationMinutes, 400)
        XCTAssertEqual(loaded.day(TestSupport.dayKey)?.note, "long day")
        XCTAssertEqual(loaded.tasks.count, original.tasks.count)
    }

    func testMissingFileYieldsDefaultsWithoutThrowing() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        let data = RoutineStorage(url: missing).load(today: TestSupport.dayKey)
        XCTAssertEqual(data.settings.startDateKey, TestSupport.dayKey)
        XCTAssertEqual(Set(data.tasks.compactMap(\.protectedPrayer)), Set(Prayer.allCases))
    }

    func testTimeOfDayAcceptsBothStoredForms() throws {
        struct Wrapper: Codable { var t: TimeOfDay }
        let asInt = try JSONDecoder().decode(Wrapper.self, from: #"{"t": 290}"#.data(using: .utf8)!)
        let asText = try JSONDecoder().decode(Wrapper.self, from: #"{"t": "04:50"}"#.data(using: .utf8)!)
        XCTAssertEqual(asInt.t, asText.t)
        XCTAssertEqual(asInt.t.hhmm, "04:50")
    }
}
