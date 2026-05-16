import Foundation

public struct ExportProgress: Sendable {
    public let currentPath: String
    public let completedCount: Int
    public let totalCount: Int

    public init(currentPath: String, completedCount: Int, totalCount: Int) {
        self.currentPath = currentPath
        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

/// Copies items with collision-safe names; zips via `/usr/bin/ditto`.
public enum ExportService: Sendable {
    public enum ExportError: Error, Sendable, LocalizedError {
        case dittoFailed(exitCode: Int32, stderr: String)

        public var errorDescription: String? {
            switch self {
            case let .dittoFailed(code, stderr):
                return "ditto exited with code \(code). \(stderr)"
            }
        }
    }

    public static func copyItems(
        _ urls: [URL],
        to destinationDirectory: URL,
        fileManager: FileManager = .default,
        onProgress: (@Sendable (ExportProgress) -> Void)? = nil
    ) async throws {
        let total = urls.count
        for (idx, src) in urls.enumerated() {
            onProgress?(ExportProgress(currentPath: src.path, completedCount: idx, totalCount: total))
            let baseName = src.lastPathComponent
            let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let dest = uniqueDestinationURL(
                directory: destinationDirectory,
                preferredName: baseName,
                isDirectory: isDir,
                fileManager: fileManager
            )
            try fileManager.copyItem(at: src, to: dest)
        }
        onProgress?(ExportProgress(currentPath: "", completedCount: total, totalCount: total))
    }

    public static func zipItems(
        _ urls: [URL],
        to zipFileURL: URL,
        onProgress: (@Sendable (ExportProgress) -> Void)? = nil
    ) async throws {
        let total = urls.count
        guard !urls.isEmpty else { return }

        let parent = zipFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: zipFileURL.path) {
            try FileManager.default.removeItem(at: zipFileURL)
        }

        for (idx, url) in urls.enumerated() {
            onProgress?(ExportProgress(currentPath: url.path, completedCount: idx, totalCount: total))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        var args = ["-c", "-k", "--keepParent"]
        args.append(contentsOf: urls.map(\.path))
        args.append(zipFileURL.path)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ExportError.dittoFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        onProgress?(ExportProgress(currentPath: zipFileURL.path, completedCount: total, totalCount: total))
    }

    // MARK: - Private

    private static func uniqueDestinationURL(
        directory: URL,
        preferredName: String,
        isDirectory: Bool,
        fileManager: FileManager
    ) -> URL {
        var candidate = directory.appendingPathComponent(preferredName, isDirectory: isDirectory)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let ns = preferredName as NSString
            let ext = ns.pathExtension
            let base = ns.deletingPathExtension
            let name: String
            if ext.isEmpty {
                name = "\(preferredName) (\(index))"
            } else {
                name = "\(base) (\(index)).\(ext)"
            }
            candidate = directory.appendingPathComponent(name, isDirectory: isDirectory)
            index += 1
        }
        return candidate
    }
}
