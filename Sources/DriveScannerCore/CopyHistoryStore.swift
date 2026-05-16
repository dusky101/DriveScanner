import Foundation

/// One entry in the copy history — records that a specific source path was migrated as part of a bundle.
public struct CopiedEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let sizeBytes: Int64
    public let copiedAt: Date
    public let bundleName: String

    public init(path: String, sizeBytes: Int64, copiedAt: Date, bundleName: String) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.copiedAt = copiedAt
        self.bundleName = bundleName
    }
}

/// Persistent record of which paths have already been migrated in past bundle runs.
public struct CopiedHistory: Codable, Sendable {
    public var entries: [CopiedEntry]

    public init(entries: [CopiedEntry] = []) {
        self.entries = entries
    }

    /// Path set for O(1) lookup in the UI.
    public var pathSet: Set<String> {
        Set(entries.map(\.path))
    }

    public func entry(for path: String) -> CopiedEntry? {
        entries.first { $0.path == path }
    }
}

/// Read/write the copy history at `~/Library/Application Support/DriveScanner/copied-history.json`.
public enum CopyHistoryStore: Sendable {
    public static let storeFolderName = "DriveScanner"
    public static let fileName = "copied-history.json"

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return support
            .appendingPathComponent(storeFolderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    public static func load(from url: URL? = nil) -> CopiedHistory {
        let target = url ?? defaultURL()
        guard let data = try? Data(contentsOf: target) else { return CopiedHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CopiedHistory.self, from: data)) ?? CopiedHistory()
    }

    public static func save(_ history: CopiedHistory, to url: URL? = nil) throws {
        let target = url ?? defaultURL()
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(history)
        try data.write(to: target, options: .atomic)
    }

    /// Returns a new history with `items` added (paths are deduplicated — re-copies update the timestamp).
    public static func append(
        items: [CandidateItem],
        bundleName: String,
        to history: CopiedHistory,
        now: Date = Date()
    ) -> CopiedHistory {
        var entries = history.entries
        let existingPaths = Set(entries.map(\.path))
        for item in items {
            let path = item.url.path
            if existingPaths.contains(path) {
                entries.removeAll { $0.path == path }
            }
            entries.append(CopiedEntry(
                path: path,
                sizeBytes: item.sizeBytes,
                copiedAt: now,
                bundleName: bundleName
            ))
        }
        return CopiedHistory(entries: entries)
    }

    public static func clear(at url: URL? = nil) {
        let target = url ?? defaultURL()
        try? FileManager.default.removeItem(at: target)
    }
}
