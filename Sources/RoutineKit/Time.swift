import Foundation

/// A wall-clock time expressed as minutes after midnight, normalised into 0..<1440.
/// Deliberately has no time-zone of its own: it is resolved against a `Calendar`
/// (always `Calendar.current` in the app) together with a specific day.
public struct TimeOfDay: Hashable, Comparable, CustomStringConvertible, Sendable {
    public var minutes: Int

    public init(minutes: Int) {
        self.minutes = ((minutes % 1440) + 1440) % 1440
    }

    public init(hour: Int, minute: Int) {
        self.init(minutes: hour * 60 + minute)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    /// Signed shift that wraps around midnight.
    public func adding(minutes delta: Int) -> TimeOfDay {
        TimeOfDay(minutes: minutes + delta)
    }

    /// Shift without wrapping; returns nil if it would cross midnight in either direction.
    public func addingWithinSameDay(minutes delta: Int) -> TimeOfDay? {
        let raw = minutes + delta
        guard raw >= 0, raw < 1440 else { return nil }
        return TimeOfDay(minutes: raw)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutes < rhs.minutes
    }

    /// "4:50 AM" — stable, locale-independent so tests can assert on it.
    public var description: String {
        let h24 = hour
        let suffix = h24 < 12 ? "AM" : "PM"
        var h12 = h24 % 12
        if h12 == 0 { h12 = 12 }
        return String(format: "%d:%02d %@", h12, minute, suffix)
    }

    /// "04:50" — the form used in persisted JSON when a string is written.
    public var hhmm: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func parse(hhmm string: String) -> TimeOfDay? {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return TimeOfDay(hour: h, minute: m)
    }
}

extension TimeOfDay: Codable {
    /// Encodes as a plain Int (minutes after midnight). Decodes from either an Int
    /// or an "HH:mm" string, so files written by the pre-schemaVersion app still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(Int.self) {
            self.init(minutes: raw)
            return
        }
        if let text = try? container.decode(String.self), let parsed = TimeOfDay.parse(hhmm: text) {
            self = parsed
            return
        }
        if let raw = try? container.decode(Double.self) {
            self.init(minutes: Int(raw.rounded()))
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected minutes-after-midnight Int or \"HH:mm\" String"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(minutes)
    }
}

/// yyyy-MM-dd keys. One formatter per calendar identity, built lazily.
public enum DateKey {
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Start-of-day `Date` for a key, in the given calendar's time zone.
    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return calendar.date(from: comps)
    }

    public static func isValid(_ key: String) -> Bool {
        date(from: key) != nil && string(from: date(from: key)!) == key
    }

    public static func today(_ calendar: Calendar = .current, now: Date = Date()) -> String {
        string(from: now, calendar: calendar)
    }

    public static func tomorrow(_ calendar: Calendar = .current, now: Date = Date()) -> String {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return string(from: next, calendar: calendar)
    }

    public static func offset(_ key: String, byDays days: Int, calendar: Calendar = .current) -> String? {
        guard let base = date(from: key, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: base) else { return nil }
        return string(from: moved, calendar: calendar)
    }

    /// Whole days between two keys (b - a). Nil if either key is malformed.
    public static func daysBetween(_ a: String, _ b: String, calendar: Calendar = .current) -> Int? {
        guard let da = date(from: a, calendar: calendar),
              let db = date(from: b, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: da, to: db).day
    }

    /// Human header for the Set Up Tomorrow screen, e.g. "Tuesday, 22 September 2026".
    public static func longDisplay(_ key: String, calendar: Calendar = .current,
                                   locale: Locale = .current) -> String {
        guard let date = date(from: key, calendar: calendar) else { return key }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: date)
    }
}

public extension Calendar {
    /// Concrete `Date` for a wall-clock time on a given yyyy-MM-dd day.
    func date(forKey key: String, at time: TimeOfDay) -> Date? {
        guard let start = DateKey.date(from: key, calendar: self) else { return nil }
        return self.date(byAdding: .minute, value: time.minutes, to: start)
    }

    /// The `DateComponents` a calendar-trigger needs for an exact date + time.
    func components(forKey key: String, at time: TimeOfDay) -> DateComponents? {
        guard let date = date(forKey: key, at: time) else { return nil }
        return dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }
}
