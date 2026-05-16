import DriveScannerCore
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

    @Test("buildTree respects max depth")
    func treeMaxDepth() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DriveScannerTree-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("a/b/c", isDirectory: true), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("a/b/c/deep.txt"), atomically: true, encoding: .utf8)

        defer { try? fm.removeItem(at: root) }

        var limits = TreeWalkLimits.default
        limits.maxDepth = 1
        limits.maxEntries = 1000

        let result = try HomeScanner.buildTree(forSelectedURLs: [root], limits: limits, fileManager: fm)
        #expect(result.rootNodes.count == 1)
        let top = result.rootNodes[0]
        #expect(top.isDirectory)
        let childA = top.children.first { $0.name == "a" }
        #expect(childA != nil)
        #expect(childA?.isDirectory == true)
        if let a = childA {
            for c in a.children {
                #expect(c.name != "c", "depth 1 should not recurse into c/")
            }
        }
    }
}

@Suite("HTMLReportBuilder")
struct HTMLReportBuilderTests {
    @Test("escape encodes HTML special characters")
    func escape() {
        #expect(HTMLReportBuilder.escape("a & b < c > \" '") == "a &amp; b &lt; c &gt; &quot; &#39;")
    }

    @Test("buildHTML includes escaped title and tree")
    func buildHTML() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DriveScannerHTML-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Filename carries angle brackets so the report must escape displayed names (content is not embedded).
        let oddName = "prefix<evil>suffix.txt"
        try "x".write(to: root.appendingPathComponent(oddName), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: root) }

        let tree = try HomeScanner.buildTree(forSelectedURLs: [root], limits: TreeWalkLimits(maxDepth: 4, maxEntries: 500), fileManager: fm)
        let html = HTMLReportBuilder.buildHTML(title: "Test <title>", tree: tree)
        #expect(html.contains("Test &lt;title&gt;"))
        #expect(html.contains("prefix&lt;evil&gt;suffix.txt"))
        #expect(html.contains("<details"))
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

        try await ExportService.copyItems([file1, file2], to: dstDir, fileManager: fm)

        #expect(fm.fileExists(atPath: dstDir.appendingPathComponent("dup.txt").path))
        #expect(fm.fileExists(atPath: dstDir.appendingPathComponent("dup (1).txt").path))
        #expect(fm.fileExists(atPath: dstDir.appendingPathComponent("dup2.txt").path))
    }

    @Test("zipItems creates a zip via ditto")
    func zipCreatesArchive() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("DriveScannerZip-\(UUID().uuidString)", isDirectory: true)
        let item = base.appendingPathComponent("item", isDirectory: true)
        try fm.createDirectory(at: item, withIntermediateDirectories: true)
        try "z".write(to: item.appendingPathComponent("inside.txt"), atomically: true, encoding: .utf8)
        let zipURL = base.appendingPathComponent("out.zip")

        defer { try? fm.removeItem(at: base) }

        try await ExportService.zipItems([item], to: zipURL)
        #expect(fm.fileExists(atPath: zipURL.path))

        let attrs = try fm.attributesOfItem(atPath: zipURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        #expect(size > 50)
    }
}
