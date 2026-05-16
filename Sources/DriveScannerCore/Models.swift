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

public enum CandidateCategory: String, Sendable, CaseIterable {
    case codeProject
    case personalData
    case devConfig
    case looseFile

    public var displayLabel: String {
        switch self {
        case .codeProject: return "Project"
        case .personalData: return "Personal"
        case .devConfig: return "Config"
        case .looseFile: return "File"
        }
    }

    /// Used by the HTML tag colour and by the macOS UI to badge rows.
    public var tagClass: String {
        switch self {
        case .codeProject: return "tag-project"
        case .personalData: return "tag-personal"
        case .devConfig: return "tag-config"
        case .looseFile: return "tag-file"
        }
    }
}

public enum CodeStack: String, Sendable, CaseIterable {
    case swift, node, python, rust, go, java, dotnet, ruby, php, generic

    public var displayLabel: String {
        switch self {
        case .swift: return "Swift"
        case .node: return "Node"
        case .python: return "Python"
        case .rust: return "Rust"
        case .go: return "Go"
        case .java: return "Java"
        case .dotnet: return ".NET"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .generic: return "Git"
        }
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

public struct CandidateItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let sizeBytes: Int64
    public let modificationDate: Date?
    public let category: CandidateCategory
    public let stack: CodeStack?

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isSymlink: Bool,
        sizeBytes: Int64,
        modificationDate: Date?,
        category: CandidateCategory,
        stack: CodeStack? = nil
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.category = category
        self.stack = stack
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

/// One rollup bucket under a scan root (e.g. `Codingapps` or `Codingapps/PedalQuest`).
public struct FolderRollupBucket: Identifiable, Sendable {
    public let id: String
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

public struct FolderRollupPerRoot: Sendable {
    public let rootURL: URL
    public let rootDisplayName: String
    public let depth1: [FolderRollupBucket]
    public let depth2: [FolderRollupBucket]
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

public struct HomebrewInfo: Sendable {
    public let brewPath: String
    public let brewfile: String
    public let formulaCount: Int
    public let caskCount: Int
    public let tapCount: Int
    public let masCount: Int

    public init(
        brewPath: String,
        brewfile: String,
        formulaCount: Int,
        caskCount: Int,
        tapCount: Int,
        masCount: Int
    ) {
        self.brewPath = brewPath
        self.brewfile = brewfile
        self.formulaCount = formulaCount
        self.caskCount = caskCount
        self.tapCount = tapCount
        self.masCount = masCount
    }

    public var isEmpty: Bool {
        formulaCount == 0 && caskCount == 0 && tapCount == 0 && masCount == 0
    }

    public var totalItems: Int {
        formulaCount + caskCount + tapCount + masCount
    }
}
