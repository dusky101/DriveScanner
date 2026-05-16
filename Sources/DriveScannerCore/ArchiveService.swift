import Foundation

/// Wraps `/usr/bin/tar` and `/usr/bin/hdiutil` to produce migration archives.
public enum ArchiveService: Sendable {
    public enum ArchiveError: Error, Sendable, LocalizedError {
        case processFailed(name: String, exitCode: Int32, stderr: String)
        case toolMissing(path: String)

        public var errorDescription: String? {
            switch self {
            case let .processFailed(name, code, stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(name) exited with code \(code). \(trimmed)"
            case let .toolMissing(path):
                return "Required tool not found: \(path)"
            }
        }
    }

    /// Creates `outputArchive` (e.g. `…/bundle.tar.gz`) by tarring `bundleDir` with its containing directory as -C root.
    public static func createTarGz(
        bundleDir: URL,
        outputArchive: URL,
        fileManager: FileManager = .default
    ) async throws {
        let tarPath = "/usr/bin/tar"
        guard fileManager.isExecutableFile(atPath: tarPath) else {
            throw ArchiveError.toolMissing(path: tarPath)
        }
        if fileManager.fileExists(atPath: outputArchive.path) {
            try fileManager.removeItem(at: outputArchive)
        }
        try fileManager.createDirectory(at: outputArchive.deletingLastPathComponent(), withIntermediateDirectories: true)

        let parent = bundleDir.deletingLastPathComponent().path
        let name = bundleDir.lastPathComponent

        try await runDetached(
            executable: tarPath,
            arguments: ["-czf", outputArchive.path, "-C", parent, name],
            stdinData: nil,
            name: "tar"
        )
    }

    /// Creates an AES-256 encrypted `.dmg` of `bundleDir`.
    /// Password is passed via stdin so it never lands on the command line.
    public static func createEncryptedDmg(
        bundleDir: URL,
        outputDmg: URL,
        volumeName: String,
        password: String,
        fileManager: FileManager = .default
    ) async throws {
        let hdiutilPath = "/usr/bin/hdiutil"
        guard fileManager.isExecutableFile(atPath: hdiutilPath) else {
            throw ArchiveError.toolMissing(path: hdiutilPath)
        }
        if fileManager.fileExists(atPath: outputDmg.path) {
            try fileManager.removeItem(at: outputDmg)
        }
        try fileManager.createDirectory(at: outputDmg.deletingLastPathComponent(), withIntermediateDirectories: true)

        let args = [
            "create",
            "-encryption", "AES-256",
            "-stdinpass",
            "-fs", "APFS",
            "-volname", volumeName,
            "-srcfolder", bundleDir.path,
            "-format", "UDZO",
            outputDmg.path,
        ]
        let pwData = (password + "\n").data(using: .utf8) ?? Data()
        try await runDetached(
            executable: hdiutilPath,
            arguments: args,
            stdinData: pwData,
            name: "hdiutil"
        )
    }

    public static func sanitizedVolumeName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ ."))
        let trimmed = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "DriveScanner-bundle" : s
    }

    // MARK: - Process helper

    private static func runDetached(
        executable: String,
        arguments: [String],
        stdinData: Data?,
        name: String
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments

            let stderrPipe = Pipe()
            task.standardError = stderrPipe
            let stdinPipe: Pipe? = stdinData != nil ? Pipe() : nil
            if let stdinPipe { task.standardInput = stdinPipe }

            try task.run()

            if let stdinPipe, let stdinData {
                try stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
                try stdinPipe.fileHandleForWriting.close()
            }

            task.waitUntilExit()

            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: errData, encoding: .utf8) ?? ""

            guard task.terminationStatus == 0 else {
                throw ArchiveError.processFailed(
                    name: name,
                    exitCode: task.terminationStatus,
                    stderr: stderr
                )
            }
        }.value
    }
}
