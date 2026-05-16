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

    /// Top-level scan: non-skipped, non-junk children of `homeURL` with shallow size metadata.
    public static func scanCandidates(
        homeURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default
    ) throws -> [CandidateItem] {
        let children = try fileManager.contentsOfDirectory(
            at: homeURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        )

        var result: [CandidateItem] = []
        result.reserveCapacity(children.count)

        for url in children {
            let name = url.lastPathComponent
            guard !shouldSkipTopLevelCandidate(name: name) else { continue }
            guard !isJunkFileName(name) else { continue }

            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .contentModificationDateKey,
            ])

            let isDir = values.isDirectory == true
            let isSymlink = values.isSymbolicLink == true
            let mod = values.contentModificationDate

            let sizeBytes: Int64
            if isDir {
                sizeBytes = try shallowDirectoryAllocatedBytes(url, fileManager: fileManager)
            } else {
                sizeBytes = allocatedBytes(from: values)
            }

            result.append(
                CandidateItem(
                    url: url,
                    name: name,
                    isDirectory: isDir,
                    isSymlink: isSymlink,
                    sizeBytes: sizeBytes,
                    modificationDate: mod
                )
            )
        }

        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    /// Walk selected roots for HTML / export (depth + entry caps).
    public static func buildTree(
        forSelectedURLs roots: [URL],
        limits: TreeWalkLimits = .default,
        fileManager: FileManager = .default
    ) throws -> TreeWalkResult {
        var visited = 0
        var truncated = false
        var rootNodes: [FileTreeNode] = []

        for root in roots.sorted(by: { $0.path < $1.path }) {
            if visited >= limits.maxEntries {
                truncated = true
                break
            }
            let (node, trunc) = try buildNode(
                url: root,
                depth: 0,
                limits: limits,
                visited: &visited,
                symlinkVisited: [],
                fileManager: fileManager
            )
            truncated = truncated || trunc
            rootNodes.append(node)
        }

        return TreeWalkResult(rootNodes: rootNodes, truncated: truncated, entriesVisited: visited)
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
                    .isRegularFileKey,
                    .totalFileAllocatedSizeKey,
                    .fileSizeKey,
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
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .totalFileAllocatedSizeKey,
                    .fileSizeKey,
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
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .totalFileAllocatedSizeKey,
                    .fileSizeKey,
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

    // MARK: - Private

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

    /// One-level sum: allocated bytes of each immediate child only (no recursion into subdirectories).
    private static func shallowDirectoryAllocatedBytes(_ dir: URL, fileManager: FileManager) throws -> Int64 {
        let items = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        )
        var sum: Int64 = 0
        for url in items {
            let name = url.lastPathComponent
            if isJunkFileName(name) { continue }
            let v = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey,
            ])
            sum += allocatedBytes(from: v)
        }
        return sum
    }

    private static func recursiveAllocatedBytes(_ root: URL, fileManager: FileManager) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            if isJunkFileName(name) { continue }
            let v = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey,
            ])
            if v.isDirectory == true { continue }
            total += allocatedBytes(from: v)
        }
        return total
    }

    private static func buildNode(
        url: URL,
        depth: Int,
        limits: TreeWalkLimits,
        visited: inout Int,
        symlinkVisited: Set<String>,
        fileManager: FileManager
    ) throws -> (FileTreeNode, Bool) {
        if visited >= limits.maxEntries {
            visited += 1
            let leaf = FileTreeNode(url: url, name: url.lastPathComponent, isDirectory: false, children: [])
            return (leaf, true)
        }

        let name = url.lastPathComponent
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])

        if values.isSymbolicLink == true {
            let path = url.path
            if symlinkVisited.contains(path) {
                visited += 1
                let leaf = FileTreeNode(
                    url: url,
                    name: "\(name) (symlink loop)",
                    isDirectory: false,
                    children: []
                )
                return (leaf, false)
            }
            var next = symlinkVisited
            next.insert(path)
            let dest = url.resolvingSymlinksInPath()
            return try buildNode(
                url: dest,
                depth: depth,
                limits: limits,
                visited: &visited,
                symlinkVisited: next,
                fileManager: fileManager
            )
        }

        let isDir = values.isDirectory == true
        if !isDir || depth >= limits.maxDepth {
            visited += 1
            return (FileTreeNode(url: url, name: name, isDirectory: isDir, children: []), false)
        }

        let childURLs = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var children: [FileTreeNode] = []
        var truncated = false

        for child in childURLs {
            if isJunkFileName(child.lastPathComponent) { continue }
            if visited >= limits.maxEntries {
                truncated = true
                break
            }
            let (node, t) = try buildNode(
                url: child,
                depth: depth + 1,
                limits: limits,
                visited: &visited,
                symlinkVisited: symlinkVisited,
                fileManager: fileManager
            )
            children.append(node)
            truncated = truncated || t
        }

        visited += 1
        return (FileTreeNode(url: url, name: name, isDirectory: true, children: children), truncated)
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
