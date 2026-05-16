@testable import DriveScannerCore
import Foundation
import Testing

@Suite("HomeScanner")
struct HomeScannerTests {
    @Test("scanCandidates skips standard home children and junk top-level names")
    func scanSkipsStandardAndJunk() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("DriveScannerTestHome-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        try fm.createDirectory(at: home.appendingPathComponent("Desktop", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("Documents", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("Pictures", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("__MACOSX", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("MyOddFolder", isDirectory: true), withIntermediateDirectories: true)
        try "hello".write(to: home.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let candidates = try HomeScanner.scanCandidates(homeURL: home, fileManager: fm)
        let names = Set(candidates.map(\.name))

        #expect(!names.contains("Desktop"))
        #expect(!names.contains("Documents"))
        #expect(!names.contains("Pictures"))
        #expect(!names.contains("__MACOSX"))
        #expect(names.contains("MyOddFolder"))
        #expect(names.contains("readme.txt"))
    }

    @Test("scanCandidates classifies categories: project / personal / config / file")
    func scanCategorisation() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("DriveScannerCat-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        // A Swift project (has Package.swift)
        let swiftProj = home.appendingPathComponent("MySwiftProj", isDirectory: true)
        try fm.createDirectory(at: swiftProj, withIntermediateDirectories: true)
        try "// swift".write(to: swiftProj.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        // Plain personal data folder (no project markers)
        try fm.createDirectory(at: home.appendingPathComponent("Recipes", isDirectory: true), withIntermediateDirectories: true)

        // A loose file
        try "data".write(to: home.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        // A dotfile
        try fm.createDirectory(at: home.appendingPathComponent(".claude", isDirectory: true), withIntermediateDirectories: true)

        let items = try HomeScanner.scanCandidates(homeURL: home, fileManager: fm)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

        #expect(byName["MySwiftProj"]?.category == .codeProject)
        #expect(byName["MySwiftProj"]?.stack == .swift)
        #expect(byName["Recipes"]?.category == .personalData)
        #expect(byName["notes.txt"]?.category == .looseFile)
        #expect(byName[".claude"]?.category == .devConfig)
    }

    @Test("scanCandidates expands parent folders with 3+ project children")
    func scanExpandsProjectParents() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("DriveScannerExpand-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        // ~/Codingapps containing 3 distinct projects + 1 non-project
        let parent = home.appendingPathComponent("Codingapps", isDirectory: true)
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let appA = parent.appendingPathComponent("AppA", isDirectory: true)
        try fm.createDirectory(at: appA, withIntermediateDirectories: true)
        try "{}".write(to: appA.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let appB = parent.appendingPathComponent("AppB", isDirectory: true)
        try fm.createDirectory(at: appB, withIntermediateDirectories: true)
        try "[package]".write(to: appB.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)

        let appC = parent.appendingPathComponent("AppC", isDirectory: true)
        try fm.createDirectory(at: appC, withIntermediateDirectories: true)
        try "// swift".write(to: appC.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let nonProj = parent.appendingPathComponent("loose-notes", isDirectory: true)
        try fm.createDirectory(at: nonProj, withIntermediateDirectories: true)

        let items = try HomeScanner.scanCandidates(homeURL: home, fileManager: fm)
        let names = items.map(\.name)
        // Parent should NOT appear as a single item — expanded
        #expect(!names.contains("Codingapps"))
        #expect(names.contains("AppA"))
        #expect(names.contains("AppB"))
        #expect(names.contains("AppC"))
        #expect(names.contains("loose-notes"))

        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        #expect(byName["AppA"]?.stack == .node)
        #expect(byName["AppB"]?.stack == .rust)
        #expect(byName["AppC"]?.stack == .swift)
        #expect(byName["loose-notes"]?.category == .personalData)
    }

    @Test("scanCandidates filters dotfile blocklist")
    func scanDotfileBlocklist() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("DriveScannerDot-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        try fm.createDirectory(at: home.appendingPathComponent(".ssh", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".Trash", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".cache", isDirectory: true), withIntermediateDirectories: true)
        try "history".write(to: home.appendingPathComponent(".zsh_history"), atomically: true, encoding: .utf8)
        try "dump".write(to: home.appendingPathComponent(".zcompdump-Marc-5.9"), atomically: true, encoding: .utf8)

        let items = try HomeScanner.scanCandidates(homeURL: home, fileManager: fm)
        let names = Set(items.map(\.name))
        #expect(names.contains(".ssh"))
        #expect(!names.contains(".Trash"))
        #expect(!names.contains(".cache"))
        #expect(!names.contains(".zsh_history"))
        #expect(!names.contains(".zcompdump-Marc-5.9"))
    }

    @Test("detectStack identifies common project markers")
    func detectStackMarkers() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DriveScannerDetect-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        func mkDir(_ path: String, with marker: String? = nil) throws -> URL {
            let dir = root.appendingPathComponent(path, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let m = marker {
                try "x".write(to: dir.appendingPathComponent(m), atomically: true, encoding: .utf8)
            }
            return dir
        }

        #expect(HomeScanner.detectStack(at: try mkDir("s", with: "Package.swift")) == .swift)
        #expect(HomeScanner.detectStack(at: try mkDir("n", with: "package.json")) == .node)
        #expect(HomeScanner.detectStack(at: try mkDir("r", with: "Cargo.toml")) == .rust)
        #expect(HomeScanner.detectStack(at: try mkDir("g", with: "go.mod")) == .go)
        #expect(HomeScanner.detectStack(at: try mkDir("p", with: "pyproject.toml")) == .python)
        #expect(HomeScanner.detectStack(at: try mkDir("j", with: "pom.xml")) == .java)
        #expect(HomeScanner.detectStack(at: try mkDir("rb", with: "Gemfile")) == .ruby)
        #expect(HomeScanner.detectStack(at: try mkDir("php", with: "composer.json")) == .php)
        #expect(HomeScanner.detectStack(at: try mkDir("nada")) == nil)
    }

    @Test("measureMediaFolderSync reports missing folder")
    func mediaMissing() {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("DriveScannerNoMedia-\(UUID().uuidString)", isDirectory: true)
        let m = HomeScanner.measureMediaFolderSync(.pictures, at: home.appendingPathComponent("Pictures", isDirectory: true), fileManager: fm)
        #expect(m.exists == false)
        #expect(m.totalBytes == 0)
    }

    @Test("measureMediaFolderSync sums file bytes under folder")
    func mediaRecursiveSize() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("DriveScannerMedia-\(UUID().uuidString)", isDirectory: true)
        let pics = home.appendingPathComponent("Pictures", isDirectory: true)
        try fm.createDirectory(at: pics.appendingPathComponent("nested", isDirectory: true), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 100).write(to: pics.appendingPathComponent("a.bin"))
        try Data(repeating: 3, count: 50).write(to: pics.appendingPathComponent("nested/b.bin"))
        defer { try? fm.removeItem(at: home) }

        let m = HomeScanner.measureMediaFolderSync(.pictures, at: pics, fileManager: fm)
        #expect(m.exists == true)
        #expect(m.totalBytes >= 150)
    }
}

@Suite("HomebrewService")
struct HomebrewServiceTests {
    @Test("parseCounts counts brew/cask/tap/mas lines and ignores comments")
    func parseCounts() {
        let brewfile = """
        # generated by `brew bundle dump`
        tap "homebrew/cask"
        tap "homebrew/bundle"
        brew "git"
        brew "wget"
        brew "ripgrep"
        cask "iterm2"
        cask "visual-studio-code"
        mas "Xcode", id: 497799835
        """
        let counts = HomebrewService.parseCounts(brewfile: brewfile)
        #expect(counts.formulae == 3)
        #expect(counts.casks == 2)
        #expect(counts.taps == 2)
        #expect(counts.mas == 1)
    }

    @Test("restoreCommand quotes the brewfile path")
    func restoreCmd() {
        #expect(HomebrewService.restoreCommand() == "brew bundle --file=\"Brewfile\"")
        #expect(HomebrewService.restoreCommand(brewfilePath: "/tmp/Brewfile") == "brew bundle --file=\"/tmp/Brewfile\"")
    }
}

@Suite("HTMLReportBuilder")
struct HTMLReportBuilderTests {
    @Test("escape encodes HTML special characters")
    func escape() {
        #expect(HTMLReportBuilder.escape("a & b < c > \" '") == "a &amp; b &lt; c &gt; &quot; &#39;")
    }

    @Test("buildReport renders hero with user name, initials avatar, and KPI cards")
    func buildReportHero() {
        let user = UserContext(
            fullName: "Ada Lovelace",
            shortName: "ada",
            hostName: "ada-mbp",
            osVersion: "macOS 15.0"
        )
        let item = CandidateItem(
            url: URL(fileURLWithPath: "/Users/ada/Codingapps"),
            name: "Codingapps",
            isDirectory: true,
            isSymlink: false,
            sizeBytes: 1024,
            modificationDate: nil,
            category: .personalData
        )
        let html = HTMLReportBuilder.buildReport(
            userContext: user,
            selectedItems: [item],
            excludedItems: [],
            rollup: FolderRollupResult(perRoot: []),
            mediaMeasurements: [],
            homebrew: nil
        )
        #expect(html.contains("Migration report — Ada Lovelace"))
        #expect(html.contains("<h1>Ada Lovelace</h1>"))
        #expect(html.contains("<div class=\"avatar\">AL</div>"))
        #expect(html.contains("Codingapps"))
        #expect(html.contains("PERSONAL"))
    }

    @Test("buildReport escapes HTML in fullName")
    func buildReportEscapesUserName() {
        let user = UserContext(
            fullName: "Evil <Name>",
            shortName: "evil",
            hostName: "host",
            osVersion: "macOS 15.0"
        )
        let html = HTMLReportBuilder.buildReport(
            userContext: user,
            selectedItems: [],
            excludedItems: [],
            rollup: FolderRollupResult(perRoot: []),
            mediaMeasurements: [],
            homebrew: nil
        )
        #expect(html.contains("<h1>Evil &lt;Name&gt;</h1>"))
        #expect(!html.contains("<h1>Evil <Name></h1>"))
    }

    @Test("buildReport renders per-folder rollup with escaped names")
    func buildReportRollup() {
        let user = UserContext(fullName: "Test User", shortName: "test", hostName: "host", osVersion: "macOS 15.0")
        let rollup = FolderRollupResult(
            perRoot: [
                FolderRollupPerRoot(
                    rootURL: URL(fileURLWithPath: "/tmp/rollup-root"),
                    rootDisplayName: "A & B < C",
                    depth1: [FolderRollupBucket(label: "Docs", totalBytes: 100, fileCount: 2)],
                    depth2: [],
                    looseFiles: []
                ),
            ]
        )
        let html = HTMLReportBuilder.buildReport(
            userContext: user,
            selectedItems: [],
            excludedItems: [],
            rollup: rollup,
            mediaMeasurements: [],
            homebrew: nil
        )
        #expect(html.contains("Inside each selected folder"))
        #expect(html.contains("<h3>A &amp; B &lt; C</h3>"))
        #expect(html.contains("Docs"))
    }

    @Test("buildReport shows project + stack tags and excluded section")
    func buildReportTagsAndExcluded() {
        let user = UserContext(fullName: "Test User", shortName: "test", hostName: "host", osVersion: "macOS 15.0")
        let project = CandidateItem(
            url: URL(fileURLWithPath: "/Users/test/MyApp"),
            name: "MyApp",
            isDirectory: true, isSymlink: false,
            sizeBytes: 5_000_000, modificationDate: nil,
            category: .codeProject, stack: .swift
        )
        let excluded = CandidateItem(
            url: URL(fileURLWithPath: "/Users/test/old-junk"),
            name: "old-junk",
            isDirectory: true, isSymlink: false,
            sizeBytes: 100, modificationDate: nil,
            category: .personalData
        )
        let html = HTMLReportBuilder.buildReport(
            userContext: user,
            selectedItems: [project],
            excludedItems: [excluded],
            rollup: FolderRollupResult(perRoot: []),
            mediaMeasurements: [],
            homebrew: nil
        )
        #expect(html.contains("PROJECT"))
        #expect(html.contains("SWIFT"))
        #expect(html.contains("Excluded (not migrating)"))
        #expect(html.contains("old-junk"))
        #expect(html.contains("section-excluded"))
    }

    @Test("buildReport renders Homebrew section with restore steps")
    func buildReportHomebrew() {
        let user = UserContext(fullName: "Test User", shortName: "test", hostName: "host", osVersion: "macOS 15.0")
        let brew = HomebrewInfo(
            brewPath: "/opt/homebrew/bin/brew",
            brewfile: "tap \"homebrew/cask\"\nbrew \"git\"\ncask \"iterm2\"\n",
            formulaCount: 1, caskCount: 1, tapCount: 1, masCount: 0
        )
        let html = HTMLReportBuilder.buildReport(
            userContext: user,
            selectedItems: [],
            excludedItems: [],
            rollup: FolderRollupResult(perRoot: []),
            mediaMeasurements: [],
            homebrew: brew
        )
        #expect(html.contains("<h2>Homebrew</h2>"))
        #expect(html.contains("/opt/homebrew/bin/brew"))
        #expect(html.contains("brew bundle --file=&quot;Brewfile&quot;"))
        #expect(html.contains("tap &quot;homebrew/cask&quot;"))
    }

    @Test("buildReport renders media folders with bytes or not-found")
    func buildReportMedia() {
        let user = UserContext(fullName: "Test User", shortName: "test", hostName: "host", osVersion: "macOS 15.0")
        let media = [
            MediaFolderMeasurement(folder: .pictures, exists: true, totalBytes: 2_000_000_000),
            MediaFolderMeasurement(folder: .movies, exists: false, totalBytes: 0),
        ]
        let html = HTMLReportBuilder.buildReport(
            userContext: user,
            selectedItems: [],
            excludedItems: [],
            rollup: FolderRollupResult(perRoot: []),
            mediaMeasurements: media,
            homebrew: nil
        )
        #expect(html.contains("Standard media folders"))
        #expect(html.contains("Pictures / Photos"))
        #expect(html.contains("not found"))
    }
}

@Suite("BundleBuilder")
struct BundleBuilderTests {
    @Test("makePlan separates devConfig items into dotfiles/ and others into data/")
    func planSplitsCategories() {
        let home = URL(fileURLWithPath: "/Users/test")
        let items = [
            CandidateItem(
                url: home.appendingPathComponent("Codingapps/DriveScanner"),
                name: "DriveScanner",
                isDirectory: true, isSymlink: false,
                sizeBytes: 1000, modificationDate: nil,
                category: .codeProject, stack: .swift
            ),
            CandidateItem(
                url: home.appendingPathComponent(".claude"),
                name: ".claude",
                isDirectory: true, isSymlink: false,
                sizeBytes: 500, modificationDate: nil,
                category: .devConfig
            ),
            CandidateItem(
                url: home.appendingPathComponent("notes.txt"),
                name: "notes.txt",
                isDirectory: false, isSymlink: false,
                sizeBytes: 100, modificationDate: nil,
                category: .looseFile
            ),
        ]
        let plan = BundleBuilder.makePlan(items: items, homeURL: home)
        let byName = Dictionary(uniqueKeysWithValues: plan.map { ($0.sourceURL.lastPathComponent, $0) })

        #expect(byName["DriveScanner"]?.kind == .data)
        #expect(byName["DriveScanner"]?.bundleRelativePath == "data/Codingapps/DriveScanner")
        #expect(byName["DriveScanner"]?.restoreRelativePath == "Codingapps/DriveScanner")

        #expect(byName[".claude"]?.kind == .dotfile)
        #expect(byName[".claude"]?.bundleRelativePath == "dotfiles/.claude")
        #expect(byName[".claude"]?.restoreRelativePath == ".claude")

        #expect(byName["notes.txt"]?.kind == .data)
        #expect(byName["notes.txt"]?.bundleRelativePath == "data/notes.txt")
    }

    @Test("renderManifest produces tab-separated lines with header comment")
    func manifestTSV() {
        let plan = [
            BundleManifestItem(
                sourceURL: URL(fileURLWithPath: "/Users/test/Codingapps/X"),
                kind: .data,
                bundleRelativePath: "data/Codingapps/X",
                restoreRelativePath: "Codingapps/X"
            ),
            BundleManifestItem(
                sourceURL: URL(fileURLWithPath: "/Users/test/.claude"),
                kind: .dotfile,
                bundleRelativePath: "dotfiles/.claude",
                restoreRelativePath: ".claude"
            ),
        ]
        let manifest = BundleBuilder.renderManifest(plan)
        let lines = manifest.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines[0].hasPrefix("#"))
        #expect(lines.contains("data\tdata/Codingapps/X\tCodingapps/X"))
        #expect(lines.contains("dotfile\tdotfiles/.claude\t.claude"))
    }

    @Test("renderRestoreScript is bash, has manifest loop, and omits brew block when no Brewfile")
    func restoreScriptShape() {
        let user = UserContext(fullName: "Ada", shortName: "ada", hostName: "h", osVersion: "macOS 15")
        let withBrew = BundleBuilder.renderRestoreScript(hasBrewfile: true, userContext: user, generatedAt: Date())
        let withoutBrew = BundleBuilder.renderRestoreScript(hasBrewfile: false, userContext: user, generatedAt: Date())

        #expect(withBrew.hasPrefix("#!/bin/bash"))
        #expect(withBrew.contains("MANIFEST=\"$BUNDLE_DIR/manifest.tsv\""))
        #expect(withBrew.contains("Brewfile present in bundle."))
        #expect(!withoutBrew.contains("Brewfile present in bundle."))
    }

    @Test("build creates bundle dir, manifest, restore.sh (0755), README, inventory, and optional Brewfile")
    func buildEndToEnd() async throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("DriveScannerBundleHome-\(UUID().uuidString)", isDirectory: true)
        let bundleDir = fm.temporaryDirectory.appendingPathComponent("DriveScannerBundleOut-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: home)
            try? fm.removeItem(at: bundleDir)
        }

        // Set up a project + a dotfile inside the fake home
        let proj = home.appendingPathComponent("Codingapps/MyApp", isDirectory: true)
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)
        try "// swift".write(to: proj.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let dot = home.appendingPathComponent(".claude", isDirectory: true)
        try fm.createDirectory(at: dot, withIntermediateDirectories: true)
        try "{}".write(to: dot.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let items = [
            CandidateItem(url: proj, name: "MyApp",
                          isDirectory: true, isSymlink: false,
                          sizeBytes: 0, modificationDate: nil,
                          category: .codeProject, stack: .swift),
            CandidateItem(url: dot, name: ".claude",
                          isDirectory: true, isSymlink: false,
                          sizeBytes: 0, modificationDate: nil,
                          category: .devConfig),
        ]
        let user = UserContext(fullName: "Ada Lovelace", shortName: "ada", hostName: "ada-mbp", osVersion: "macOS 15.0")

        let result = try await BundleBuilder.build(
            bundleURL: bundleDir,
            selectedItems: items,
            homeURL: home,
            userContext: user,
            htmlReport: "<!doctype html><html><body>hello</body></html>",
            brewfile: "tap \"homebrew/cask\"\nbrew \"git\"\n"
        )

        #expect(result.copiedCount == 2)
        #expect(result.skippedCount == 0)

        // Bundle layout
        #expect(fm.fileExists(atPath: bundleDir.appendingPathComponent("README.txt").path))
        #expect(fm.fileExists(atPath: bundleDir.appendingPathComponent("manifest.tsv").path))
        #expect(fm.fileExists(atPath: bundleDir.appendingPathComponent("inventory.html").path))
        #expect(fm.fileExists(atPath: bundleDir.appendingPathComponent("Brewfile").path))
        #expect(fm.fileExists(atPath: bundleDir.appendingPathComponent("data/Codingapps/MyApp/Package.swift").path))
        #expect(fm.fileExists(atPath: bundleDir.appendingPathComponent("dotfiles/.claude/settings.json").path))

        // restore.sh is executable
        let restorePath = bundleDir.appendingPathComponent("restore.sh").path
        #expect(fm.fileExists(atPath: restorePath))
        let attrs = try fm.attributesOfItem(atPath: restorePath)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        #expect(perms & 0o111 != 0, "restore.sh should be executable")

        // Brewfile content preserved
        let brewfileContent = try String(contentsOfFile: bundleDir.appendingPathComponent("Brewfile").path, encoding: .utf8)
        #expect(brewfileContent.contains("brew \"git\""))
    }

    @Test("defaultBundleName uses short name and ISO-style date")
    func defaultName() {
        let user = UserContext(fullName: "Ada Lovelace", shortName: "ada", hostName: "h", osVersion: "macOS 15")
        let date = Date(timeIntervalSince1970: 1_715_817_600)  // 2024-05-16 UTC
        let name = BundleBuilder.defaultBundleName(userContext: user, date: date)
        #expect(name.hasPrefix("DriveScanner-ada-"))
        // YYYY-MM-DD pattern at the end
        let suffix = String(name.suffix(10))
        #expect(suffix.matches(of: try! Regex(#"^\d{4}-\d{2}-\d{2}$"#)).count == 1)
    }
}

@Suite("ArchiveService")
struct ArchiveServiceTests {
    @Test("createTarGz round-trips a small bundle")
    func tarGzRoundTrip() async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("DriveScannerTar-\(UUID().uuidString)", isDirectory: true)
        let bundle = work.appendingPathComponent("bundle", isDirectory: true)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "alpha".write(to: bundle.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: bundle.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: work) }

        let archive = work.appendingPathComponent("bundle.tar.gz")
        try await ArchiveService.createTarGz(bundleDir: bundle, outputArchive: archive)

        #expect(fm.fileExists(atPath: archive.path))
        let size = (try? fm.attributesOfItem(atPath: archive.path)[.size] as? Int) ?? 0
        #expect(size > 0)
    }

    @Test("sanitizedVolumeName strips disallowed characters")
    func volumeName() {
        #expect(ArchiveService.sanitizedVolumeName("Ada/Migration:Bundle") == "Ada-Migration-Bundle")
        #expect(ArchiveService.sanitizedVolumeName("   ") == "DriveScanner-bundle")
        #expect(ArchiveService.sanitizedVolumeName("My_Bundle 2026-05-16") == "My_Bundle 2026-05-16")
    }
}

@Suite("ExportService")
struct ExportServiceTests {
    @Test("copyItems uses numeric suffix on collision")
    func copyCollision() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("DriveScannerCopy-\(UUID().uuidString)", isDirectory: true)
        let srcDir = base.appendingPathComponent("src", isDirectory: true)
        let dstDir = base.appendingPathComponent("dst", isDirectory: true)
        try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

        let file1 = srcDir.appendingPathComponent("dup.txt")
        let file2 = srcDir.appendingPathComponent("dup2.txt")
        try "a".write(to: file1, atomically: true, encoding: .utf8)
        try "b".write(to: file2, atomically: true, encoding: .utf8)
        try "existing".write(to: dstDir.appendingPathComponent("dup.txt"), atomically: true, encoding: .utf8)

        defer { try? fm.removeItem(at: base) }

        try await ExportService.copyItems([file1, file2], to: dstDir)
        let listing = try fm.contentsOfDirectory(atPath: dstDir.path).sorted()
        #expect(listing.contains("dup.txt"))
        #expect(listing.contains("dup (1).txt"))
        #expect(listing.contains("dup2.txt"))
    }

    @Test("zipItems creates a zip via ditto")
    func zipCreates() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("DriveScannerZip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let src = base.appendingPathComponent("payload.txt")
        try "payload".write(to: src, atomically: true, encoding: .utf8)

        let zipURL = base.appendingPathComponent("out.zip")
        try await ExportService.zipItems([src], to: zipURL)
        #expect(fm.fileExists(atPath: zipURL.path))
        let attrs = try fm.attributesOfItem(atPath: zipURL.path)
        #expect((attrs[.size] as? Int ?? 0) > 0)
    }
}
