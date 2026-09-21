import Foundation

public enum TaskCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case wake, hygiene, prayer, quran, skincare, gym, meal, sleep, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wake: return "Wake"
        case .hygiene: return "Hygiene"
        case .prayer: return "Prayers"
        case .quran: return "Quran"
        case .skincare: return "Skincare"
        case .gym: return "Gym"
        case .meal: return "Meals"
        case .sleep: return "Sleep"
        case .other: return "Other"
        }
    }

    /// Order used when grouping a day detail view.
    public var sortOrder: Int {
        switch self {
        case .wake: return 0
        case .hygiene: return 1
        case .prayer: return 2
        case .quran: return 3
        case .skincare: return 4
        case .gym: return 5
        case .meal: return 6
        case .sleep: return 7
        case .other: return 8
        }
    }

    /// Spellings used by older builds, mapped on read only.
    private static let legacyAliases: [String: TaskCategory] = [
        "fitness": .gym, "workout": .gym, "exercise": .gym,
        "food": .meal, "meals": .meal, "dinner": .meal,
        "prayers": .prayer, "salah": .prayer,
        "quraan": .quran, "reading": .quran,
        "skin": .skincare, "bedtime": .sleep, "morning": .wake
    ]

    /// Tolerant: an unrecognised category from an older file becomes `.other`.
    public init(from decoder: Decoder) throws {
        let raw = ((try? decoder.singleValueContainer().decode(String.self)) ?? "other").lowercased()
        self = TaskCategory(rawValue: raw) ?? TaskCategory.legacyAliases[raw] ?? .other
    }
}

/// How a task gets its time. Exactly two kinds - nothing else may move a task.
public enum TaskTiming: Hashable, Sendable {
    /// Minutes after midnight, same every day.
    case fixed(TimeOfDay)
    /// Prayer + signed offset in minutes (negative = before the adhan).
    case anchored(prayer: Prayer, offset: Int)

    public var isAnchored: Bool {
        if case .anchored = self { return true }
        return false
    }

    public var anchorPrayer: Prayer? {
        if case .anchored(let prayer, _) = self { return prayer }
        return nil
    }

    public var offset: Int {
        if case .anchored(_, let offset) = self { return offset }
        return 0
    }

    public var fixedTime: TimeOfDay? {
        if case .fixed(let time) = self { return time }
        return nil
    }

    /// "Fajr - 10 min" / "Maghrib + 15 min" / "8:40 PM"
    public var describedShort: String {
        switch self {
        case .fixed(let time):
            return time.description
        case .anchored(let prayer, let offset):
            if offset == 0 { return prayer.displayName }
            let sign = offset < 0 ? "-" : "+"
            return "\(prayer.displayName) \(sign) \(abs(offset)) min"
        }
    }
}

extension TaskTiming: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, minutes, prayer, offset
        // Legacy (pre-schemaVersion) spellings, accepted on read only:
        case time, anchor, anchorPrayer, offsetMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(String.self, forKey: .kind)?.lowercased()

        var prayerRaw = try c.decodeIfPresent(String.self, forKey: .prayer)
        if prayerRaw == nil { prayerRaw = try c.decodeIfPresent(String.self, forKey: .anchor) }
        if prayerRaw == nil { prayerRaw = try c.decodeIfPresent(String.self, forKey: .anchorPrayer) }
        let prayer = prayerRaw.flatMap { Prayer(rawValue: $0.lowercased()) }

        var offset = try c.decodeIfPresent(Int.self, forKey: .offset)
        if offset == nil { offset = try c.decodeIfPresent(Int.self, forKey: .offsetMinutes) }

        var minutes = try c.decodeIfPresent(TimeOfDay.self, forKey: .minutes)
        if minutes == nil { minutes = try c.decodeIfPresent(TimeOfDay.self, forKey: .time) }

        // Explicit kind wins; otherwise infer from whichever payload is present.
        if kind == "anchored", let prayer = prayer {
            self = .anchored(prayer: prayer, offset: offset ?? 0)
        } else if kind == "fixed", let minutes = minutes {
            self = .fixed(minutes)
        } else if let prayer = prayer {
            self = .anchored(prayer: prayer, offset: offset ?? 0)
        } else if let minutes = minutes {
            self = .fixed(minutes)
        } else {
            // Last resort so one malformed task never blocks the whole file.
            self = .fixed(TimeOfDay(hour: 9, minute: 0))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixed(let time):
            try c.encode("fixed", forKey: .kind)
            try c.encode(time, forKey: .minutes)
        case .anchored(let prayer, let offset):
            try c.encode("anchored", forKey: .kind)
            try c.encode(prayer.rawValue, forKey: .prayer)
            try c.encode(offset, forKey: .offset)
        }
    }
}

public struct ChecklistStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled
    }
}

public struct RoutineTask: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String?
    public var category: TaskCategory
    public var timing: TaskTiming
    public var alarm: Bool
    public var insistent: Bool
    public var onlyWhenGoingOut: Bool
    public var enabled: Bool
    public var steps: [ChecklistStep]

    /// Set only on the five obligatory prayer tasks. A non-nil value makes the
    /// task protected: it cannot be deleted or disabled and its alarm stays on.
    public var protectedPrayer: Prayer?

    /// Preparation tasks (brush teeth / wudu) - editable, but the UI warns first.
    public var isPrayerPreparation: Bool

    public init(id: UUID = UUID(),
                title: String,
                note: String? = nil,
                category: TaskCategory,
                timing: TaskTiming,
                alarm: Bool = true,
                insistent: Bool = false,
                onlyWhenGoingOut: Bool = false,
                enabled: Bool = true,
                steps: [ChecklistStep] = [],
                protectedPrayer: Prayer? = nil,
                isPrayerPreparation: Bool = false) {
        self.id = id
        self.title = title
        self.note = note
        self.category = category
        self.timing = timing
        self.alarm = alarm
        self.insistent = insistent
        self.onlyWhenGoingOut = onlyWhenGoingOut
        self.enabled = enabled
        self.steps = steps
        self.protectedPrayer = protectedPrayer
        self.isPrayerPreparation = isPrayerPreparation
    }

    public var isProtected: Bool { protectedPrayer != nil }

    /// Protected prayers are force-corrected on read so that no hand-edited or
    /// legacy file can ever deliver a disabled / silent obligatory prayer.
    public var normalised: RoutineTask {
        guard let prayer = protectedPrayer else { return self }
        var copy = self
        copy.enabled = true
        copy.alarm = true
        copy.onlyWhenGoingOut = false
        if copy.timing.anchorPrayer != prayer {
            copy.timing = .anchored(prayer: prayer, offset: 0)
        }
        return copy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        note = try c.decodeIfPresent(String.self, forKey: .note)
        category = try c.decodeIfPresent(TaskCategory.self, forKey: .category) ?? .other
        // v1 nests the timing under "timing". v0 wrote its fields inline on the
        // task itself, so fall back to reading them from this same container
        // before giving up on a placeholder.
        if let nested = try c.decodeIfPresent(TaskTiming.self, forKey: .timing) {
            timing = nested
        } else if let inline = try RoutineTask.inlineTiming(from: c) {
            timing = inline
        } else {
            timing = .fixed(TimeOfDay(hour: 9, minute: 0))
        }
        alarm = try c.decodeIfPresent(Bool.self, forKey: .alarm) ?? true
        insistent = try c.decodeIfPresent(Bool.self, forKey: .insistent) ?? false
        onlyWhenGoingOut = try c.decodeIfPresent(Bool.self, forKey: .onlyWhenGoingOut) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        steps = try c.decodeIfPresent([ChecklistStep].self, forKey: .steps) ?? []
        let raw = try c.decodeIfPresent(String.self, forKey: .protectedPrayer)
        protectedPrayer = raw.flatMap { Prayer(rawValue: $0.lowercased()) }
        isPrayerPreparation = try c.decodeIfPresent(Bool.self, forKey: .isPrayerPreparation) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(category.rawValue, forKey: .category)
        try c.encode(timing, forKey: .timing)
        try c.encode(alarm, forKey: .alarm)
        try c.encode(insistent, forKey: .insistent)
        try c.encode(onlyWhenGoingOut, forKey: .onlyWhenGoingOut)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(steps, forKey: .steps)
        try c.encodeIfPresent(protectedPrayer?.rawValue, forKey: .protectedPrayer)
        try c.encode(isPrayerPreparation, forKey: .isPrayerPreparation)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, note, category, timing, alarm, insistent
        case onlyWhenGoingOut, enabled, steps, protectedPrayer, isPrayerPreparation
        // v0 wrote the timing inline on the task. Read-only.
        case time, minutes, anchor, anchorPrayer, prayer, offset, offsetMinutes
    }

    /// Reads a v0 task's inline timing fields. An anchor wins over a fixed
    /// time if a file somehow carries both. Returns nil when neither is there.
    private static func inlineTiming(from c: KeyedDecodingContainer<CodingKeys>) throws -> TaskTiming? {
        var prayerRaw = try c.decodeIfPresent(String.self, forKey: .prayer)
        if prayerRaw == nil { prayerRaw = try c.decodeIfPresent(String.self, forKey: .anchor) }
        if prayerRaw == nil { prayerRaw = try c.decodeIfPresent(String.self, forKey: .anchorPrayer) }

        if let prayer = prayerRaw.flatMap({ Prayer(rawValue: $0.lowercased()) }) {
            var offset = try c.decodeIfPresent(Int.self, forKey: .offset)
            if offset == nil { offset = try c.decodeIfPresent(Int.self, forKey: .offsetMinutes) }
            return .anchored(prayer: prayer, offset: offset ?? 0)
        }

        var fixed = try c.decodeIfPresent(TimeOfDay.self, forKey: .time)
        if fixed == nil { fixed = try c.decodeIfPresent(TimeOfDay.self, forKey: .minutes) }
        if let fixed = fixed { return .fixed(fixed) }

        return nil
    }
}

/// Why an edit to a task was refused or needs confirming.
public enum TaskEditGuard: Equatable {
    case allowed
    case refused(String)
    case needsConfirmation(String)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    public var isRefused: Bool {
        if case .refused = self { return true }
        return false
    }

    public var message: String? {
        switch self {
        case .allowed: return nil
        case .refused(let text), .needsConfirmation(let text): return text
        }
    }
}

public enum TaskRules {
    public static func canDelete(_ task: RoutineTask) -> TaskEditGuard {
        if let prayer = task.protectedPrayer {
            return .refused("\(prayer.displayName) is an obligatory prayer and cannot be deleted.")
        }
        if task.isPrayerPreparation {
            return .needsConfirmation("\(task.title) prepares you for prayer. Delete it anyway?")
        }
        return .allowed
    }

    public static func canDisable(_ task: RoutineTask) -> TaskEditGuard {
        if let prayer = task.protectedPrayer {
            return .refused("\(prayer.displayName) is an obligatory prayer and cannot be turned off.")
        }
        if task.isPrayerPreparation {
            return .needsConfirmation("\(task.title) prepares you for prayer. Turn it off anyway?")
        }
        return .allowed
    }

    public static func canMuteAlarm(_ task: RoutineTask) -> TaskEditGuard {
        if let prayer = task.protectedPrayer {
            return .refused("The \(prayer.displayName) alarm cannot be turned off.")
        }
        return .allowed
    }
}
