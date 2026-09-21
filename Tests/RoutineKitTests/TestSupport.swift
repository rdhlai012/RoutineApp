import Foundation
import XCTest
@testable import RoutineKit

/// A fixed IST calendar so every assertion is reproducible on any machine.
/// The app itself always uses `Calendar.current`; only the tests pin it.
enum TestSupport {
    static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(secondsFromGMT: 19800)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    static let startKey = "2026-09-01"
    static let dayKey = "2026-09-21"
    static let nextKey = "2026-09-22"

    /// 04:58 / 12:15 / 15:38 / 18:24 / 19:35
    static func times(fajr: Int = 4 * 60 + 58,
                      dhuhr: Int = 12 * 60 + 15,
                      asr: Int = 15 * 60 + 38,
                      maghrib: Int = 18 * 60 + 24,
                      isha: Int = 19 * 60 + 35) -> PrayerTimes {
        PrayerTimes(fajr: TimeOfDay(minutes: fajr),
                    dhuhr: TimeOfDay(minutes: dhuhr),
                    asr: TimeOfDay(minutes: asr),
                    maghrib: TimeOfDay(minutes: maghrib),
                    isha: TimeOfDay(minutes: isha))
    }

    static func data(withTimesOn keys: [String] = []) -> RoutineData {
        var data = RoutineData.makeDefault(startDateKey: startKey)
        for key in keys {
            data.mutateDay(key) { $0.prayerTimes = times() }
        }
        return data
    }

    /// Midnight on `key`, so "now" never accidentally drops the whole day.
    static func startOfDay(_ key: String) -> Date {
        DateKey.date(from: key, calendar: calendar)!
    }

    static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    static func task(_ data: RoutineData, _ id: UUID) -> RoutineTask {
        data.task(id)!
    }

    static func plannedTime(_ planned: [PlannedTask], _ id: UUID) -> TimeOfDay? {
        planned.first { $0.id == id }?.time
    }
}
