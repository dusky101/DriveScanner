import Foundation

/// Enumerates `~/` for migration candidates and measures standard media folders.
public enum HomeScanner: Sendable {
    /// Immediate children of `~` excluded from the *candidate* list (case-insensitive name match).
    public static let skippedHomeChildNames: Set<String> = [
        "desktop", "documents", "downloads", "library",
        "movies", "music", "pictures", "public", "applications",
    ]

    public static let junkFileNames: Set<String> = [
        ".ds_store",
        "icon\r",
        ".localized",
        ".appledouble",
        "__macosx",
    ]

    /// Hidden top-level entries we never include (caches, history, regenerable junk).
    public static let dotfileBlocklist: Set<String> = [
        ".trash", ".cache", ".local", ".ds_store", ".cfusertextencoding",
        ".zsh_history", ".zsh_sessions", ".python_history", ".viminfo", ".lesshst",
        ".vscode-shared", ".templateengine",
        ".snowflake", ".streamlit",
        ".npm",
        ".bash_sessions",
    ]

    /// Hidden top-level entries we recognise as developer-relevant.
    public static let knownDotfiles: Set<String> = [
        ".claude", ".claude-flow", ".claude.json", ".claude.json.backup",
        ".cursor", ".codex", ".copilot", ".continue", ".codeium", ".codebuddy",
        ".augment", ".gemini", ".iflow", ".qwen", ".openhands", ".cagent",
        ".mcpjam", ".otk", ".trae", ".trae-cn", ".qoder", ".vibe",
        ".factory", ".pochi", ".commandcode", ".openclaw", ".agents",
        ".neovate", ".junie", ".kilocode", ".kiro", ".kode", ".roo",
        ".rprodlx", ".zencoder",
        ".vscode", ".oh-my-zsh",
        ".dotnet", ".nuget", ".nvm", ".npm-global", ".rustup", ".swiftpm",
        ".gem", ".docker",
        ".aws", ".azure", ".gcloud", ".kube",
        ".zshrc", ".bashrc", ".zprofile", ".bash_profile",
        ".gitconfig", ".gitignore_global", ".npmrc", ".yarnrc",
        ".ssh", ".gnupg",
        ".config", ".rest-client", ".servicehub", ".office-addin-dev-certs",
    ]

    /// Pattern-based dotfile excludes (e.g. `.zcompdump-*`).
    public static let dotfileBlockPrefixes: [String] = [
        ".zcompdump",
    ]

    /// Top-level scan: visible non-skipped non-junk entries plus dev-relevant dotfiles.
    /// Folders whose ≥3 immediate children look like project roots are expanded one level.
    public static func scanCandidates(
        homeURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default
    ) throws -> [CandidateItem] {
        var result: [CandidateItem] = []

        let visible = try fileManager.contentsOfDirectory(
            at: homeURL,
            includingPropertiesForKeys: candidateResourceKeys,
            options: [.skipsHiddenFiles]
        )

        for url in visible {
            let name = url.lastPathComponent
            guard !shouldSkipTopLevelCandidate(name: name) else { continue }
            guard !isJunkFileName(name) else { continue }

            let values = try url.resourceValues(forKeys: candidateResourceKeySet)
            let isDir = values.isDirectory == true
            let isSymlink = values.isSymbolicLink == true

            if isDir, !isSymlink, let expanded = try? maybeExpandParent(url: url, fileManager: fileManager) {
                result.append(contentsOf: expanded)
                continue
            }

            let stack = (isDir && !isSymlink) ? detectStack(at: url, fileManager: fileManager) : nil
            let category: CandidateCategory
            if !isDir {
                category = .looseFile
            } else if stack != nil {
                category = .codeProject
            } else {
                category = .personalData
            }

            let item = try makeCandidate(
                url: url,
                name: name,
                values: values,
                category: category,
                stack: stack,
                fileManager: fileManager
            )
            result.append(item)
        }

        // Dotfile pass — explicit, since `.skipsHiddenFiles` filtered them out above.
        let hiddenChildren = try fileManager.contentsOfDirectory(
            at: homeURL,
            includingPropertiesForKeys: candidateResourceKeys,
            options: []
        )
        for url in hiddenChildren {
            let name = url.lastPathComponent
            guard name.hasPrefix("."), !isJunkFileName(name) else { continue }
            let lower = name.lowercased()
            if dotfileBlocklist.contains(lower) { continue }
            if dotfileBlockPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }

            let values = try url.resourceValues(forKeys: candidateResourceKeySet)
            let item = try makeCandidate(
                url: url,
                name: name,
                values: values,
                category: .devConfig,
                stack: nil,
                fileManager: fileManager
            )
            result.append(item)
        }

        result.sort { lhs, rhs in
            if lhs.category != rhs.category {
                return categoryOrder(lhs.category) < categoryOrder(rhs.category)
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return result
    }

    /// Recursive on-disk size for `~/Pictures`, `~/Music`, or `~/Movies`.
    public static func measureMediaFolder(
        _ folder: MediaFolder,
        homeURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default
    ) async -> MediaFolderMeasurement {
        let url = homeURL.appendingPathComponent(folder.directoryName, isDirectory: true)
        await Task.yield()
        return measureMediaFolderSync(folder, at: url, fileManager: fileManager)
    }

    public static func measureMediaFolderSync(
        _ folder: MediaFolder,
        at url: URL,
        fileManager: FileManager = .default
    ) -> MediaFolderMeasurement {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return MediaFolderMeasurement(folder: folder, exists: false, totalBytes: 0)
        }
        do {
            let total = try recursiveAllocatedBytes(url, fileManager: fileManager)
            return MediaFolderMeasurement(folder: folder, exists: true, totalBytes: total)
        } catch {
            return MediaFolderMeasurement(folder: folder, exists: true, totalBytes: 0)
        }
    }

    /// Per-root folder rollups for HTML: depth-1 / depth-2 aggregates and loose (root-level) files.
    public static func buildFolderRollup(
        forSelectedURLs roots: [URL],
        fileManager: FileManager = .default
    ) throws -> FolderRollupResult {
        var perRoot: [FolderRollupPerRoot] = []

        for root in roots.sorted(by: { $0.path < $1.path }) {
            let canonical = rollupCanonicalRoot(root, fileManager: fileManager)
            var depth1Map: [String: (bytes: Int64, count: Int)] = [:]
            var depth2Map: [String: (bytes: Int64, count: Int)] = [:]
            var looseMap: [String: (bytes: Int64, count: Int)] = [:]

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: canonical.path, isDirectory: &isDir) else {
                perRoot.append(
                    FolderRollupPerRoot(
                        rootURL: root,
                        rootDisplayName: canonical.lastPathComponent,
                        depth1: [],
                        depth2: [],
                        looseFiles: []
                    )
                )
                continue
            }

            if !isDir.boolValue {
                let values = try canonical.resourceValues(forKeys: [
                    .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
                ])
                if values.isRegularFile == true {
                    let b = allocatedBytes(from: values)
                    let label = canonical.lastPathComponent
                    looseMap[label] = (b, 1)
                }
                perRoot.append(
                    FolderRollupPerRoot(
                        rootURL: root,
                        rootDisplayName: canonical.lastPathComponent,
                        depth1: [],
                        depth2: [],
                        looseFiles: rollupBuckets(from: looseMap)
                    )
                )
                continue
            }

            let rootPath = rollupNormalizedPath(canonical.path)
            guard let enumerator = fileManager.enumerator(
                at: canonical,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
                ],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                perRoot.append(
                    FolderRollupPerRoot(
                        rootURL: root,
                        rootDisplayName: canonical.lastPathComponent,
                        depth1: [],
                        depth2: [],
                        looseFiles: []
                    )
                )
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                let name = url.lastPathComponent
                if isJunkFileName(name) { continue }

                let v = try url.resourceValues(forKeys: [
                    .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
                ])
                if v.isDirectory == true { continue }
                if v.isRegularFile != true { continue }

                let bytes = allocatedBytes(from: v)
                let fullPath = rollupNormalizedPath(url.path)
                let rel = rollupRelativePath(rootPath: rootPath, fullPath: fullPath)
                guard !rel.isEmpty else { continue }

                let parts = rel.split(separator: "/").map(String.init)
                guard let first = parts.first else { continue }

                if parts.count == 1 {
                    let cur = looseMap[first] ?? (0, 0)
                    looseMap[first] = (cur.bytes + bytes, cur.count + 1)
                } else {
                    let cur1 = depth1Map[first] ?? (0, 0)
                    depth1Map[first] = (cur1.bytes + bytes, cur1.count + 1)
                    if parts.count >= 3 {
                        let label2 = "\(parts[0])/\(parts[1])"
                        let cur2 = depth2Map[label2] ?? (0, 0)
                        depth2Map[label2] = (cur2.bytes + bytes, cur2.count + 1)
                    }
                }
            }

            perRoot.append(
                FolderRollupPerRoot(
                    rootURL: root,
                    rootDisplayName: canonical.lastPathComponent,
                    depth1: rollupBuckets(from: depth1Map),
                    depth2: rollupBuckets(from: depth2Map),
                    looseFiles: rollupBuckets(from: looseMap)
                )
            )
        }

        return FolderRollupResult(perRoot: perRoot)
    }

    /// Returns the detected stack if the URL is a project root, else nil.
    public static func detectStack(at url: URL, fileManager: FileManager = .default) -> CodeStack? {
        let path = url.path
        func has(_ relative: String) -> Bool {
            fileManager.fileExists(atPath: "\(path)/\(relative)")
        }
        if has("Package.swift") { return .swift }
        if has("Cargo.toml") { return .rust }
        if has("go.mod") { return .go }
        if has("pyproject.toml") || has("setup.py") || has("requirements.txt") || has("Pipfile") { return .python }
        if has("package.json") { return .node }
        if has("pom.xml") || has("build.gradle") || has("build.gradle.kts") { return .java }
        if has("Gemfile") { return .ruby }
        if has("composer.json") { return .php }
        if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
            for entry in contents {
                if entry.hasSuffix(".csproj") || entry.hasSuffix(".sln") || entry.hasSuffix(".fsproj") {
                    return .dotnet
                }
            }
        }
        if has(".git") { return .generic }
        return nil
    }

    // MARK: - Private

    private static let candidateResourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
    ]

    private static let candidateResourceKeySet: Set<URLResourceKey> = Set(candidateResourceKeys)

    /// Expand a parent into per-project (and per-non-project) rows when ≥3 children look like project roots.
    /// Returns nil when no expansion should happen.
    private static func maybeExpandParent(url: URL, fileManager: FileManager) throws -> [CandidateItem]? {
        if detectStack(at: url, fileManager: fileManager) != nil { return nil }

        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: candidateResourceKeys,
            options: [.skipsHiddenFiles]
        )
        var inspected: [(url: URL, isDir: Bool, isSymlink: Bool, stack: CodeStack?)] = []
        var projectChildCount = 0
        for child in children {
            let n = child.lastPathComponent
            if isJunkFileName(n) { continue }
            let v = try child.resourceValues(forKeys: candidateResourceKeySet)
            let isDir = v.isDirectory == true
            let isSymlink = v.isSymbolicLink == true
            let stack = (isDir && !isSymlink) ? detectStack(at: child, fileManager: fileManager) : nil
            if stack != nil { projectChildCount += 1 }
            inspected.append((child, isDir, isSymlink, stack))
        }

        guard projectChildCount >= 3 else { return nil }

        var out: [CandidateItem] = []
        for child in inspected {
            let n = child.url.lastPathComponent
            let values = try child.url.resourceValues(forKeys: candidateResourceKeySet)
            let category: CandidateCategory
            if !child.isDir {
                category = .looseFile
            } else if child.stack != nil {
                category = .codeProject
            } else {
                category = .personalData
            }
            let item = try makeCandidate(
                url: child.url,
                name: n,
                values: values,
                category: category,
                stack: child.stack,
                fileManager: fileManager
            )
            out.append(item)
        }
        return out
    }

    private static func makeCandidate(
        url: URL,
        name: String,
        values: URLResourceValues,
        category: CandidateCategory,
        stack: CodeStack?,
        fileManager: FileManager
    ) throws -> CandidateItem {
        let isDir = values.isDirectory == true
        let isSymlink = values.isSymbolicLink == true
        let sizeBytes: Int64
        if isDir, !isSymlink {
            sizeBytes = (try? shallowDirectoryAllocatedBytes(url, fileManager: fileManager)) ?? 0
        } else {
            sizeBytes = allocatedBytes(from: values)
        }
        return CandidateItem(
            url: url,
            name: name,
            isDirectory: isDir,
            isSymlink: isSymlink,
            sizeBytes: sizeBytes,
            modificationDate: values.contentModificationDate,
            category: category,
            stack: stack
        )
    }

    private static func categoryOrder(_ c: CandidateCategory) -> Int {
        switch c {
        case .codeProject: return 0
        case .personalData: return 1
        case .devConfig: return 2
        case .looseFile: return 3
        }
    }

    private static func shouldSkipTopLevelCandidate(name: String) -> Bool {
        skippedHomeChildNames.contains(name.lowercased())
    }

    private static func isJunkFileName(_ name: String) -> Bool {
        junkFileNames.contains(name.lowercased())
    }

    private static func allocatedBytes(from values: URLResourceValues) -> Int64 {
        if let n = values.totalFileAllocatedSize { return Int64(n) }
        if let n = values.fileSize { return Int64(n) }
        return 0
    }

    private static func shallowDirectoryAllocatedBytes(_ dir: URL, fileManager: FileManager) throws -> Int64 {
        let items = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        )
        var sum: Int64 = 0
        for url in items {
            let name = url.lastPathComponent
            if isJunkFileName(name) { continue }
            let v = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
            ])
            sum += allocatedBytes(from: v)
        }
        return sum
    }

    private static func recursiveAllocatedBytes(_ root: URL, fileManager: FileManager) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
            ],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            if isJunkFileName(name) { continue }
            let v = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
            ])
            if v.isDirectory == true { continue }
            total += allocatedBytes(from: v)
        }
        return total
    }

    private static func rollupCanonicalRoot(_ url: URL, fileManager: FileManager) -> URL {
        let std = url.standardizedFileURL
        let v = try? std.resourceValues(forKeys: [.isSymbolicLinkKey])
        if v?.isSymbolicLink == true {
            return std.resolvingSymlinksInPath().standardizedFileURL
        }
        return std
    }

    private static func rollupNormalizedPath(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") {
            p.removeLast()
        }
        return p
    }

    private static func rollupRelativePath(rootPath: String, fullPath: String) -> String {
        guard fullPath != rootPath else { return "" }
        guard fullPath.hasPrefix(rootPath) else { return "" }
        var start = fullPath.index(fullPath.startIndex, offsetBy: rootPath.count)
        if start < fullPath.endIndex, fullPath[start] == "/" {
            start = fullPath.index(after: start)
        }
        return String(fullPath[start...])
    }

    private static func rollupBuckets(from map: [String: (bytes: Int64, count: Int)]) -> [FolderRollupBucket] {
        map.map { label, pair in
            FolderRollupBucket(label: label, totalBytes: pair.bytes, fileCount: pair.count)
        }
        .sorted {
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }
}
