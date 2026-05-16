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
