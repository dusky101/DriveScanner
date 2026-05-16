import Foundation

public enum BundleFormat: String, Sendable, CaseIterable, Identifiable {
    case folder
    case targz
    case encryptedDmg

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .folder: return "Plain folder"
        case .targz: return "tar.gz archive"
        case .encryptedDmg: return "Encrypted DMG (recommended for USB)"
        }
    }

    public var fileExtension: String? {
        switch self {
        case .folder: return nil
        case .targz: return "tar.gz"
        case .encryptedDmg: return "dmg"
        }
    }
}

public struct BundleManifestItem: Sendable {
    public enum Kind: String, Sendable {
        case data
        case dotfile
    }
    public let sourceURL: URL
    public let kind: Kind
    public let bundleRelativePath: String
    public let restoreRelativePath: String

    public init(sourceURL: URL, kind: Kind, bundleRelativePath: String, restoreRelativePath: String) {
        self.sourceURL = sourceURL
        self.kind = kind
        self.bundleRelativePath = bundleRelativePath
        self.restoreRelativePath = restoreRelativePath
    }
}

public struct BundleResult: Sendable {
    public let bundleURL: URL
    public let manifest: [BundleManifestItem]
    public let copiedCount: Int
    public let skippedCount: Int

    public init(bundleURL: URL, manifest: [BundleManifestItem], copiedCount: Int, skippedCount: Int) {
        self.bundleURL = bundleURL
        self.manifest = manifest
        self.copiedCount = copiedCount
        self.skippedCount = skippedCount
    }
}

/// Assembles a migration bundle on disk: README, manifest, restore.sh, inventory.html,
/// optional Brewfile, plus the selected payload mirrored under `data/` and `dotfiles/`.
public enum BundleBuilder: Sendable {
    public static func build(
        bundleURL: URL,
        selectedItems: [CandidateItem],
        homeURL: URL,
        userContext: UserContext,
        htmlReport: String,
        fileSearchHtml: String? = nil,
        brewfile: String?,
        generatedAt: Date = Date(),
        fileManager: FileManager = .default,
        onProgress: (@Sendable (ExportProgress) -> Void)? = nil
    ) async throws -> BundleResult {
        if fileManager.fileExists(atPath: bundleURL.path) {
            try fileManager.removeItem(at: bundleURL)
        }
        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let dataDir = bundleURL.appendingPathComponent("data", isDirectory: true)
        let dotfilesDir = bundleURL.appendingPathComponent("dotfiles", isDirectory: true)
        try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dotfilesDir, withIntermediateDirectories: true)

        let plan = makePlan(items: selectedItems, homeURL: homeURL)
        var copied = 0
        var skipped = 0
        let total = plan.count

        for (idx, entry) in plan.enumerated() {
            onProgress?(ExportProgress(currentPath: entry.sourceURL.path, completedCount: idx, totalCount: total))
            let dest = bundleURL.appendingPathComponent(entry.bundleRelativePath)
            let destParent = dest.deletingLastPathComponent()
            do {
                if !fileManager.fileExists(atPath: destParent.path) {
                    try fileManager.createDirectory(at: destParent, withIntermediateDirectories: true)
                }
                try fileManager.copyItem(at: entry.sourceURL, to: dest)
                copied += 1
            } catch {
                skipped += 1
            }
        }
        onProgress?(ExportProgress(currentPath: "", completedCount: total, totalCount: total))

        let manifestText = renderManifest(plan)
        try manifestText.write(
            to: bundleURL.appendingPathComponent("manifest.tsv"),
            atomically: true,
            encoding: .utf8
        )

        let restoreText = renderRestoreScript(hasBrewfile: brewfile != nil, userContext: userContext, generatedAt: generatedAt)
        let restoreURL = bundleURL.appendingPathComponent("restore.sh")
        try restoreText.write(to: restoreURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: restoreURL.path)

        let readme = renderReadme(
            userContext: userContext,
            generatedAt: generatedAt,
            itemCount: plan.count,
            hasBrewfile: brewfile != nil,
            hasFileSearch: fileSearchHtml != nil
        )
        try readme.write(to: bundleURL.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        try htmlReport.write(to: bundleURL.appendingPathComponent("inventory.html"), atomically: true, encoding: .utf8)

        if let fileSearchHtml {
            try fileSearchHtml.write(to: bundleURL.appendingPathComponent("file-search.html"), atomically: true, encoding: .utf8)
        }

        if let brewfile {
            try brewfile.write(to: bundleURL.appendingPathComponent("Brewfile"), atomically: true, encoding: .utf8)
        }

        return BundleResult(bundleURL: bundleURL, manifest: plan, copiedCount: copied, skippedCount: skipped)
    }

    /// Suggested default bundle name: `DriveScanner-<shortName>-<YYYY-MM-DD>`.
    public static func defaultBundleName(userContext: UserContext, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        let shortName = userContext.shortName.isEmpty ? "user" : userContext.shortName
        return "DriveScanner-\(shortName)-\(formatter.string(from: date))"
    }

    // MARK: - Plan

    static func makePlan(items: [CandidateItem], homeURL: URL) -> [BundleManifestItem] {
        let homePath = homeURL.path
        return items.map { item -> BundleManifestItem in
            let restoreRel = relativePath(from: homePath, to: item.url.path)
                ?? item.url.lastPathComponent
            if item.category == .devConfig {
                let bundleRel = "dotfiles/\(item.url.lastPathComponent)"
                return BundleManifestItem(
                    sourceURL: item.url,
                    kind: .dotfile,
                    bundleRelativePath: bundleRel,
                    restoreRelativePath: item.url.lastPathComponent
                )
            } else {
                let bundleRel = "data/\(restoreRel)"
                return BundleManifestItem(
                    sourceURL: item.url,
                    kind: .data,
                    bundleRelativePath: bundleRel,
                    restoreRelativePath: restoreRel
                )
            }
        }
    }

    static func relativePath(from base: String, to full: String) -> String? {
        let trimmedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard full.hasPrefix(trimmedBase + "/") else { return nil }
        let start = full.index(full.startIndex, offsetBy: trimmedBase.count + 1)
        return String(full[start...])
    }

    // MARK: - Manifest TSV

    static func renderManifest(_ plan: [BundleManifestItem]) -> String {
        var lines = ["# kind\tbundle_path\trestore_path"]
        for entry in plan {
            lines.append("\(entry.kind.rawValue)\t\(entry.bundleRelativePath)\t\(entry.restoreRelativePath)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Restore script

    static func renderRestoreScript(hasBrewfile: Bool, userContext: UserContext, generatedAt: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "en_GB")
        let dateStr = dateFormatter.string(from: generatedAt)
        let userLine = userContext.fullName.isEmpty ? userContext.shortName : userContext.fullName

        let brewBlock = hasBrewfile ? brewBlockBash : ""

        return """
        #!/bin/bash
        # DriveScanner migration restore
        # Generated for \(userLine) on \(dateStr)
        # Bundle layout:
        #   manifest.tsv    list of items to restore
        #   data/           regular folders/files, restored to $HOME/<path>
        #   dotfiles/       hidden config dirs/files, restored to $HOME/<name>
        #   Brewfile        Homebrew bundle (optional)
        #   inventory.html  human-readable inventory of what's in this bundle

        set -eu

        BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
        MANIFEST="$BUNDLE_DIR/manifest.tsv"

        if [ ! -f "$MANIFEST" ]; then
          echo "ERROR: manifest.tsv not found in $BUNDLE_DIR" >&2
          exit 1
        fi

        echo "DriveScanner migration restore"
        echo "Bundle: $BUNDLE_DIR"
        echo "Target user: $USER (HOME=$HOME)"
        echo ""

        ADDED=0
        SKIPPED=0
        MISSING=0

        while IFS=$'\\t' read -r kind bundle_path restore_path; do
          [ -z "${kind:-}" ] && continue
          case "$kind" in '#'*) continue ;; esac

          src="$BUNDLE_DIR/$bundle_path"
          target="$HOME/$restore_path"

          if [ ! -e "$src" ]; then
            echo "MISSING $bundle_path"
            MISSING=$((MISSING + 1))
            continue
          fi

          if [ -e "$target" ]; then
            echo "SKIP    $restore_path (already exists)"
            SKIPPED=$((SKIPPED + 1))
            continue
          fi

          target_dir="$(dirname "$target")"
          if [ "$target_dir" != "$HOME" ]; then
            mkdir -p "$target_dir"
          fi
          cp -R "$src" "$target"
          echo "ADDED   $restore_path"
          ADDED=$((ADDED + 1))
        done < "$MANIFEST"

        echo ""
        echo "Restore summary: $ADDED added, $SKIPPED skipped, $MISSING missing"
        echo ""
        \(brewBlock)
        echo "Done."
        """
    }

    private static let brewBlockBash: String = """
    if [ -f "$BUNDLE_DIR/Brewfile" ]; then
      echo "Brewfile present in bundle."
      if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is not installed on this Mac."
        echo "Install with:"
        echo "  /bin/bash -c \\"\\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\""
        echo "Then run: brew bundle --file=\\"$BUNDLE_DIR/Brewfile\\""
      else
        printf "Run 'brew bundle' now to restore packages? [y/N] "
        if [ -t 0 ]; then
          read -r ans
        else
          read -r ans </dev/tty || ans=""
        fi
        case "$ans" in
          y|Y)
            brew bundle --file="$BUNDLE_DIR/Brewfile"
            ;;
          *)
            echo "Skipped. Restore later with: brew bundle --file=\\"$BUNDLE_DIR/Brewfile\\""
            ;;
        esac
      fi
      echo ""
    fi
    """

    // MARK: - README

    static func renderReadme(userContext: UserContext, generatedAt: Date, itemCount: Int, hasBrewfile: Bool, hasFileSearch: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "en_GB")
        let dateStr = dateFormatter.string(from: generatedAt)
        let brewLine = hasBrewfile ? "  Brewfile          - your Homebrew packages (formulae, casks, taps)\n" : ""
        let searchLine = hasFileSearch ? "  file-search.html  - in-browser search across every file name in the bundle\n" : ""
        return """
        DriveScanner migration bundle
        =============================

        Generated for: \(userContext.fullName) (\(userContext.shortName))
        Date:          \(dateStr)
        Source Mac:    \(userContext.hostName) (\(userContext.osVersion))
        Items:         \(itemCount)

        Contents
        --------
          README.txt        - this file
          inventory.html    - open in a browser for a full readable report
        \(searchLine)  manifest.tsv      - tab-separated item list used by restore.sh
          restore.sh        - run this on the new Mac to restore
          data/             - your selected folders and files (mirrors $HOME/...)
          dotfiles/         - your developer configs (.claude, .ssh, .vscode, etc.)
        \(brewLine)
        To restore on the new Mac
        -------------------------
          1. Mount or extract this bundle so it's a folder on the new Mac.
          2. Open Terminal in that folder.
          3. Run:  bash ./restore.sh
          4. If a Brewfile is present, the script will prompt to install/restore packages.

        Safety
        ------
          - restore.sh NEVER overwrites existing files at $HOME.
          - Existing paths are SKIPPED with a log line.
          - You can re-run restore.sh safely; it is idempotent.

        Generated by DriveScanner.
        """
    }
}
