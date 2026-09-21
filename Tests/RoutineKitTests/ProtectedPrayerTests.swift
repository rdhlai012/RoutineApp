import XCTest
@testable import RoutineKit

final class ProtectedPrayerTests: XCTestCase {

    func testAllFivePrayersExistByDefault() {
        let data = TestSupport.data()
        let prayers = data.tasks.compactMap(\.protectedPrayer)
        XCTAssertEqual(Set(prayers), Set(Prayer.allCases))
        XCTAssertEqual(prayers.count, 5, "exactly one protected task per prayer")
    }

    func testEveryPrayerHasBrushWuduAndPrayer() {
        let data = TestSupport.data(withTimesOn: [TestSupport.dayKey])
        for prayer in Prayer.allCases {
            let anchored = data.tasks.filter { $0.timing.anchorPrayer == prayer && $0.enabled }
            XCTAssertTrue(anchored.contains { $0.title == "Brush teeth" || prayer == .fajr },
                          "\(prayer.displayName) needs a brush-teeth step")
            XCTAssertTrue(anchored.contains { $0.title == "Wudu" },
                          "\(prayer.displayName) needs a wudu step")
            XCTAssertTrue(anchored.contains { $0.protectedPrayer == prayer },
                          "\(prayer.displayName) needs the prayer itself")
        }
        // Fajr's brush is fixed-time (04:55) because the bath comes before it.
        XCTAssertEqual(data.task(DefaultTaskID.brushMorning)?.timing.fixedTime,
                       TimeOfDay(hour: 4, minute: 55))
    }

    func testIshaIsEnabledByDefault() {
        let data = TestSupport.data()
        for id in [DefaultTaskID.ishaBrush, DefaultTaskID.ishaWudu, DefaultTaskID.ishaPrayer] {
            XCTAssertEqual(data.task(id)?.enabled, true, "Isha is not optional")
        }
    }

    func testProtectedPrayersCannotBeDeleted() {
        var data = TestSupport.data()
        for prayer in Prayer.allCases {
            let task = data.tasks.first { $0.protectedPrayer == prayer }!
            let result = data.deleteTask(task.id, confirmed: true)
            XCTAssertTrue(result.isRefused, "\(prayer.displayName) must not be deletable")
            XCTAssertNotNil(data.task(task.id))
        }
        XCTAssertEqual(data.tasks.compactMap(\.protectedPrayer).count, 5)
    }

    func testProtectedPrayersCannotBeDisabledOrMuted() {
        var data = TestSupport.data()
        var isha = data.task(DefaultTaskID.ishaPrayer)!

        isha.enabled = false
        XCTAssertTrue(data.updateTask(isha, confirmed: true).isRefused)
        XCTAssertEqual(data.task(DefaultTaskID.ishaPrayer)?.enabled, true)

        isha = data.task(DefaultTaskID.ishaPrayer)!
        isha.alarm = false
        XCTAssertTrue(data.updateTask(isha, confirmed: true).isRefused)
        XCTAssertEqual(data.task(DefaultTaskID.ishaPrayer)?.alarm, true)
    }

    func testOffsetAndNoteOnAProtectedPrayerAreEditable() {
        var data = TestSupport.data()
        var maghrib = data.task(DefaultTaskID.maghribPrayer)!
        maghrib.timing = .anchored(prayer: .maghrib, offset: 7)
        maghrib.note = "Masjid al-Noor"
        XCTAssertTrue(data.updateTask(maghrib).isAllowed)

        let saved = data.task(DefaultTaskID.maghribPrayer)!
        XCTAssertEqual(saved.timing.offset, 7)
        XCTAssertEqual(saved.note, "Masjid al-Noor")
        XCTAssertEqual(saved.timing.anchorPrayer, .maghrib)
    }

    func testResetToDefaultsRecreatesAllFivePrayers() {
        var data = TestSupport.data()
        // Strip them out behind the API's back, as a corrupt file might.
        data.tasks.removeAll { $0.isProtected }
        XCTAssertTrue(data.tasks.compactMap(\.protectedPrayer).isEmpty)

        data.resetTasksToDefaults()
        XCTAssertEqual(Set(data.tasks.compactMap(\.protectedPrayer)), Set(Prayer.allCases))
        for task in data.tasks where task.isProtected {
            XCTAssertTrue(task.enabled)
            XCTAssertTrue(task.alarm)
        }
    }

    func testCorruptFileIsRepairedOnLoad() {
        var data = TestSupport.data()
        // Disabled, silent, wrongly anchored - all three must be corrected.
        if let index = data.tasks.firstIndex(where: { $0.id == DefaultTaskID.asrPrayer }) {
            data.tasks[index].enabled = false
            data.tasks[index].alarm = false
            data.tasks[index].timing = .fixed(TimeOfDay(hour: 3, minute: 0))
        }
        data.ensureProtectedPrayers()

        let asr = data.task(DefaultTaskID.asrPrayer)!
        XCTAssertTrue(asr.enabled)
        XCTAssertTrue(asr.alarm)
        XCTAssertEqual(asr.timing.anchorPrayer, .asr)
    }

    func testPreparationTasksWarnButAreEditable() {
        var data = TestSupport.data()
        var wudu = data.task(DefaultTaskID.dhuhrWudu)!
        wudu.enabled = false

        let warning = data.updateTask(wudu)
        if case .needsConfirmation = warning {} else {
            XCTFail("Disabling wudu should warn first, got \(warning)")
        }
        XCTAssertEqual(data.task(DefaultTaskID.dhuhrWudu)?.enabled, true, "not applied without confirmation")

        XCTAssertTrue(data.updateTask(wudu, confirmed: true).isAllowed)
        XCTAssertEqual(data.task(DefaultTaskID.dhuhrWudu)?.enabled, false)
    }

    func testDeletingAPreparationTaskNeedsConfirmation() {
        var data = TestSupport.data()
        if case .needsConfirmation = data.deleteTask(DefaultTaskID.fajrWudu) {} else {
            XCTFail("Deleting wudu should warn first")
        }
        XCTAssertNotNil(data.task(DefaultTaskID.fajrWudu))

        XCTAssertTrue(data.deleteTask(DefaultTaskID.fajrWudu, confirmed: true).isAllowed)
        XCTAssertNil(data.task(DefaultTaskID.fajrWudu))
    }

    func testOrdinaryTasksDeleteWithoutFuss() {
        var data = TestSupport.data()
        XCTAssertTrue(data.deleteTask(DefaultTaskID.dinner).isAllowed)
        XCTAssertNil(data.task(DefaultTaskID.dinner))
    }

    // MARK: Set Up Tomorrow gating

    func testSaveIsBlockedUntilAllFiveAreEntered() {
        var draft = PrayerTimesDraft()
        XCTAssertFalse(TomorrowSetup.canSave(draft))

        let full = TestSupport.times()
        for prayer in Prayer.allCases.dropLast() {
            draft[prayer] = full[prayer]
            XCTAssertFalse(TomorrowSetup.canSave(draft),
                           "still missing \(draft.missing.map(\.displayName))")
        }
        XCTAssertEqual(draft.missing, [.isha])
        XCTAssertNotNil(TomorrowSetup.saveBlockedReason(draft))
        XCTAssertTrue(TomorrowSetup.saveBlockedReason(draft)!.contains("Isha"))

        draft[.isha] = full.isha
        XCTAssertTrue(TomorrowSetup.canSave(draft))
        XCTAssertNil(TomorrowSetup.saveBlockedReason(draft))
    }

    func testEachMissingPrayerBlocksTheSaveOnItsOwn() {
        for prayer in Prayer.allCases {
            var draft = PrayerTimesDraft(TestSupport.times())
            draft[prayer] = nil
            XCTAssertFalse(TomorrowSetup.canSave(draft),
                           "missing \(prayer.displayName) must block the save")
            XCTAssertEqual(draft.missing, [prayer])
        }
    }

    func testDraftOutOfOrderBlocksTheSave() {
        var draft = PrayerTimesDraft(TestSupport.times())
        draft[.maghrib] = TimeOfDay(hour: 14, minute: 0)     // before Asr 15:38
        XCTAssertFalse(TomorrowSetup.canSave(draft))
        XCTAssertTrue(TomorrowSetup.saveBlockedReason(draft)!.contains("Maghrib"))
    }

    func testPreviewDoesNotMutateStoredData() {
        let data = TestSupport.data()
        let (schedule, _) = TomorrowSetup.preview(dateKey: TestSupport.nextKey,
                                                  times: TestSupport.times(),
                                                  data: data)
        XCTAssertTrue(schedule.allSatisfy(\.isResolved))
        XCTAssertNil(data.prayerTimes(on: TestSupport.nextKey),
                     "a preview must never save anything")
    }
}
