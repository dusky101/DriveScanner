import Foundation

/// Detects Homebrew on the current Mac and produces a `Brewfile` via `brew bundle dump`.
/// Returns nil when brew is not installed at either standard prefix.
public enum HomebrewService: Sendable {
    public static let brewCandidatePaths: [String] = [
        "/opt/homebrew/bin/brew",   // Apple Silicon
        "/usr/local/bin/brew",      // Intel
    ]

    public static func enumerate(fileManager: FileManager = .default) async -> HomebrewInfo? {
        guard let brewPath = brewCandidatePaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        guard let output = await Task.detached(priority: .userInitiated, operation: {
            runProcess(brewPath, arguments: ["bundle", "dump", "--file=-"])
        }).value else {
            return nil
        }
        let counts = parseCounts(brewfile: output)
        return HomebrewInfo(
            brewPath: brewPath,
            brewfile: output,
            formulaCount: counts.formulae,
            caskCount: counts.casks,
            tapCount: counts.taps,
            masCount: counts.mas
        )
    }

    /// Recommended one-liner the user runs on the new Mac after installing Homebrew.
    public static func restoreCommand(brewfilePath: String = "Brewfile") -> String {
        "brew bundle --file=\"\(brewfilePath)\""
    }

    // MARK: - Internal

    struct BrewCounts: Sendable {
        var formulae: Int = 0
        var casks: Int = 0
        var taps: Int = 0
        var mas: Int = 0
    }

    static func parseCounts(brewfile: String) -> BrewCounts {
        var counts = BrewCounts()
        for raw in brewfile.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("brew ") { counts.formulae += 1 }
            else if line.hasPrefix("cask ") { counts.casks += 1 }
            else if line.hasPrefix("tap ")  { counts.taps += 1 }
            else if line.hasPrefix("mas ")  { counts.mas += 1 }
        }
        return counts
    }

    private static func runProcess(_ path: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
