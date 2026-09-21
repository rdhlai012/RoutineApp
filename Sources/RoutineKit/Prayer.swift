import Foundation

/// The five daily prayers. All five are mandatory everywhere in this app.
public enum Prayer: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fajr, dhuhr, asr, maghrib, isha

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fajr: return "Fajr"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }

    /// Canonical order within a day. Used for validation and display.
    public var order: Int {
        switch self {
        case .fajr: return 0
        case .dhuhr: return 1
        case .asr: return 2
        case .maghrib: return 3
        case .isha: return 4
        }
    }
}

/// The exact adhan times for ONE specific date. There is no such thing as a
/// partially-filled `PrayerTimes`: it only exists once all five are known.
public struct PrayerTimes: Codable, Hashable, Sendable {
    public var fajr: TimeOfDay
    public var dhuhr: TimeOfDay
    public var asr: TimeOfDay
    public var maghrib: TimeOfDay
    public var isha: TimeOfDay

    public init(fajr: TimeOfDay, dhuhr: TimeOfDay, asr: TimeOfDay, maghrib: TimeOfDay, isha: TimeOfDay) {
        self.fajr = fajr; self.dhuhr = dhuhr; self.asr = asr; self.maghrib = maghrib; self.isha = isha
    }

    public subscript(prayer: Prayer) -> TimeOfDay {
        get {
            switch prayer {
            case .fajr: return fajr
            case .dhuhr: return dhuhr
            case .asr: return asr
            case .maghrib: return maghrib
            case .isha: return isha
            }
        }
        set {
            switch prayer {
            case .fajr: fajr = newValue
            case .dhuhr: dhuhr = newValue
            case .asr: asr = newValue
            case .maghrib: maghrib = newValue
            case .isha: isha = newValue
            }
        }
    }

    public var all: [(Prayer, TimeOfDay)] {
        Prayer.allCases.map { ($0, self[$0]) }
    }

    /// Tolerant decoding: a file missing any one of the five is NOT a valid
    /// `PrayerTimes` and fails, which is what we want — no partial days.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fajr = try c.decode(TimeOfDay.self, forKey: .fajr)
        dhuhr = try c.decode(TimeOfDay.self, forKey: .dhuhr)
        asr = try c.decode(TimeOfDay.self, forKey: .asr)
        maghrib = try c.decode(TimeOfDay.self, forKey: .maghrib)
        isha = try c.decode(TimeOfDay.self, forKey: .isha)
    }
}

/// A draft of the five times where any of them may still be missing.
/// This is what the "Set Up Tomorrow" editor binds to.
public struct PrayerTimesDraft: Equatable, Sendable {
    public var values: [Prayer: TimeOfDay]

    public init(values: [Prayer: TimeOfDay] = [:]) {
        self.values = values
    }

    public init(_ times: PrayerTimes) {
        values = Dictionary(uniqueKeysWithValues: times.all)
    }

    public subscript(prayer: Prayer) -> TimeOfDay? {
        get { values[prayer] }
        set { values[prayer] = newValue }
    }

    public var missing: [Prayer] {
        Prayer.allCases.filter { values[$0] == nil }
    }

    public var isComplete: Bool { missing.isEmpty }

    /// Nil unless all five are present. Order is NOT checked here — see `validate`.
    public var completed: PrayerTimes? {
        guard let f = values[.fajr], let d = values[.dhuhr], let a = values[.asr],
              let m = values[.maghrib], let i = values[.isha] else { return nil }
        return PrayerTimes(fajr: f, dhuhr: d, asr: a, maghrib: m, isha: i)
    }
}

public enum PrayerTimesValidationError: Error, Equatable, CustomStringConvertible {
    case missing([Prayer])
    case outOfOrder(earlier: Prayer, later: Prayer)

    public var description: String {
        switch self {
        case .missing(let prayers):
            let names = prayers.map(\.displayName).joined(separator: ", ")
            return prayers.count == 1
                ? "\(names) time is missing."
                : "These prayer times are missing: \(names)."
        case .outOfOrder(let earlier, let later):
            return "\(later.displayName) must be after \(earlier.displayName), and all five must fall on the same day."
        }
    }

    public var message: String { description }
}

public enum PrayerTimesValidator {
    /// fajr < dhuhr < asr < maghrib < isha, all within the same calendar day.
    /// Because `TimeOfDay` is minutes-after-midnight, strict ascending order
    /// already guarantees "same day" — nothing wraps past midnight.
    public static func validate(_ draft: PrayerTimesDraft) -> Result<PrayerTimes, PrayerTimesValidationError> {
        let missing = draft.missing
        guard missing.isEmpty, let times = draft.completed else {
            return .failure(.missing(missing))
        }
        return validate(times)
    }

    public static func validate(_ times: PrayerTimes) -> Result<PrayerTimes, PrayerTimesValidationError> {
        let ordered = Prayer.allCases
        for index in 1..<ordered.count {
            let earlier = ordered[index - 1]
            let later = ordered[index]
            if times[later] <= times[earlier] {
                return .failure(.outOfOrder(earlier: earlier, later: later))
            }
        }
        return .success(times)
    }
}
