import Foundation

/// Reads and writes routine.json. Foundation only, so the migration path is
/// testable on any platform.
public struct RoutineStorage {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func documentsURL(fileName: String = "routine.json") -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return directory.appendingPathComponent(fileName)
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func decode(_ data: Data) throws -> RoutineData {
        try JSONDecoder().decode(RoutineData.self, from: data)
    }

    /// Loads, migrating whatever is on disk. A missing or unreadable file
    /// yields a fresh default routine rather than throwing, so the app always
    /// starts; `loadStrict` is available when a caller wants the error.
    public func load(today: String = DateKey.today()) -> RoutineData {
        do {
            return try loadStrict(today: today)
        } catch {
            return RoutineData.makeDefault(startDateKey: today)
        }
    }

    public func loadStrict(today: String = DateKey.today()) throws -> RoutineData {
        let raw = try Data(contentsOf: url)
        var decoded = try RoutineStorage.decode(raw)
        decoded.migrateInPlace(today: today)
        return decoded
    }

    public func save(_ data: RoutineData) throws {
        let encoded = try RoutineStorage.makeEncoder().encode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
    }

    /// Keeps one copy of the previous file before the first v1 write, so a
    /// failed migration is recoverable by hand.
    public func backupIfNeeded(suffix: String = ".v0.backup") throws {
        let backup = URL(fileURLWithPath: url.path + suffix)
        guard FileManager.default.fileExists(atPath: url.path),
              !FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.copyItem(at: url, to: backup)
    }
}
