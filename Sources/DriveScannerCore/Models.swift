import Foundation

public enum MediaFolder: String, CaseIterable, Sendable {
    case pictures = "Pictures"
    case music = "Music"
    case movies = "Movies"

    public var displayLabel: String {
        switch self {
        case .pictures: return "Pictures / Photos"
        case .music: return "Music"
        case .movies: return "Movies"
        }
    }

    public var directoryName: String { rawValue }
}

public struct CandidateItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let sizeBytes: Int64
    public let modificationDate: Date?

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isSymlink: Bool,
        sizeBytes: Int64,
        modificationDate: Date?
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.id = url.path(percentEncoded: false)
    }
}

public struct UserContext: Sendable {
    public let fullName: String
    public let shortName: String
    public let hostName: String
    public let osVersion: String

    public init(fullName: String, shortName: String, hostName: String, osVersion: String) {
        self.fullName = fullName
        self.shortName = shortName
        self.hostName = hostName
        self.osVersion = osVersion
    }

    public var initials: String {
        let parts = fullName.split(separator: " ", omittingEmptySubsequences: true)
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        let combined = (first + last).uppercased()
        if !combined.isEmpty { return combined }
        let fallback = shortName.first.map { String($0).uppercased() } ?? "?"
        return fallback
    }
}

public struct MediaFolderMeasurement: Sendable {
    public let folder: MediaFolder
    public let exists: Bool
    public let totalBytes: Int64

    public init(folder: MediaFolder, exists: Bool, totalBytes: Int64) {
        self.folder = folder
        self.exists = exists
        self.totalBytes = totalBytes
    }
}

public struct ScanSummary: Sendable {
    public let candidates: [CandidateItem]
    public let mediaMeasurements: [MediaFolderMeasurement]

    public init(candidates: [CandidateItem], mediaMeasurements: [MediaFolderMeasurement]) {
        self.candidates = candidates
        self.mediaMeasurements = mediaMeasurements
    }
}

public struct TreeWalkLimits: Sendable {
    public var maxDepth: Int
    public var maxEntries: Int

    public static let `default` = TreeWalkLimits(maxDepth: 12, maxEntries: 10_000)

    public init(maxDepth: Int, maxEntries: Int) {
        self.maxDepth = maxDepth
        self.maxEntries = maxEntries
    }
}

public struct TreeWalkResult: Sendable {
    public let rootNodes: [FileTreeNode]
    public let truncated: Bool
    public let entriesVisited: Int

    public init(rootNodes: [FileTreeNode], truncated: Bool, entriesVisited: Int) {
        self.rootNodes = rootNodes
        self.truncated = truncated
        self.entriesVisited = entriesVisited
    }
}

/// One rollup bucket under a scan root (e.g. `Codingapps` or `Codingapps/PedalQuest`).
public struct FolderRollupBucket: Identifiable, Sendable {
    public let id: String
    /// Display label (first segment, or `first/second`).
    public let label: String
    public let totalBytes: Int64
    public let fileCount: Int

    public init(label: String, totalBytes: Int64, fileCount: Int) {
        self.label = label
        self.totalBytes = totalBytes
        self.fileCount = fileCount
        self.id = label
    }
}

/// Rollup for one selected root URL.
public struct FolderRollupPerRoot: Sendable {
    public let rootURL: URL
    public let rootDisplayName: String
    public let depth1: [FolderRollupBucket]
    public let depth2: [FolderRollupBucket]
    /// Files whose path under root has no directory component (loose at root).
    public let looseFiles: [FolderRollupBucket]

    public init(
        rootURL: URL,
        rootDisplayName: String,
        depth1: [FolderRollupBucket],
        depth2: [FolderRollupBucket],
        looseFiles: [FolderRollupBucket]
    ) {
        self.rootURL = rootURL
        self.rootDisplayName = rootDisplayName
        self.depth1 = depth1
        self.depth2 = depth2
        self.looseFiles = looseFiles
    }
}

public struct FolderRollupResult: Sendable {
    public let perRoot: [FolderRollupPerRoot]

    public init(perRoot: [FolderRollupPerRoot]) {
        self.perRoot = perRoot
    }
}

public struct FileTreeNode: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let children: [FileTreeNode]

    public init(url: URL, name: String, isDirectory: Bool, children: [FileTreeNode]) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
        self.id = url.path(percentEncoded: false)
    }
}
