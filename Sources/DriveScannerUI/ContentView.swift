import AppKit
import DriveScannerCore
import SwiftUI

public struct ContentView: View {
    public init() {}

    // MARK: - State

    @State private var candidates: [CandidateItem] = []
    @State private var topLevelFolders: [TopLevelFolder] = []
    @State private var selection: Set<CandidateItem.ID> = []
    @State private var searchText = ""
    @State private var scanError: String?
    @State private var isScanning = false
    @State private var mediaMeasurements: [MediaFolder: MediaFolderMeasurement] = [:]
    @State private var mediaLoading: Set<MediaFolder> = Set(MediaFolder.allCases)
    @State private var homebrewInfo: HomebrewInfo?
    @State private var brewLoading = false
    @State private var statusMessage = ""
    @State private var isExporting = false
    @State private var showingBundleSheet = false
    @State private var showingBrewDetail = false
    @State private var showingClearHistoryAlert = false
    @State private var measuringIDs: Set<CandidateItem.ID> = []
    @State private var fileNamesByID: [CandidateItem.ID: [String]] = [:]
    @State private var copyHistory: CopiedHistory = CopiedHistory()
    @State private var allowRecopy: Bool = false
    @State private var sortOrder: [KeyPathComparator<CandidateItem>] = [
        .init(\.sizeBytes, order: .reverse)
    ]
    @State private var topLevelSortOrder: [KeyPathComparator<TopLevelFolder>] = [
        .init(\.sizeBytes, order: .reverse)
    ]

    // MARK: - Derived

    private var candidatesByID: [CandidateItem.ID: CandidateItem] {
        Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
    }

    private var canExport: Bool {
        !selection.isEmpty && !isExporting && measuringIDs.isEmpty
    }

    private var isMeasuring: Bool { !measuringIDs.isEmpty }

    private var measurementProgress: (done: Int, total: Int)? {
        let dirs = candidates.filter { $0.isDirectory && !$0.isSymlink }
        guard !dirs.isEmpty else { return nil }
        let done = dirs.count - dirs.filter { measuringIDs.contains($0.id) }.count
        guard done < dirs.count else { return nil }
        return (done, dirs.count)
    }

    private var previouslyCopiedIDs: Set<CandidateItem.ID> {
        copyHistory.pathSet
    }

    private var selectedTotalBytes: Int64 {
        selection.reduce(Int64(0)) { total, id in
            total + (candidatesByID[id]?.sizeBytes ?? 0)
        }
    }

    private var topLevelSelectedCount: Int {
        topLevelFolders.reduce(0) { count, folder in
            count + (folder.childIDs.contains { selection.contains($0) } ? 1 : 0)
        }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 14) {
            ScanHeader(
                userContext: currentUserContext(),
                hasScanned: !candidates.isEmpty,
                isScanning: isScanning,
                isExporting: isExporting,
                measurementProgress: measurementProgress,
                onScan: { Task { await runScan() } }
            )
            OverviewSection(
                mediaMeasurements: mediaMeasurements,
                mediaLoading: mediaLoading,
                homebrewInfo: homebrewInfo,
                brewLoading: brewLoading,
                onOpenHomebrew: { showingBrewDetail = true }
            )

            HStack(alignment: .top, spacing: 20) {
                TopLevelFoldersSection(
                    folders: $topLevelFolders,
                    selection: $selection,
                    sortOrder: $topLevelSortOrder,
                    measuringIDs: measuringIDs,
                    previouslyCopiedIDs: previouslyCopiedIDs,
                    allowRecopy: allowRecopy,
                    selectedCount: topLevelSelectedCount,
                    selectedBytes: selectedTotalBytes
                )
                .frame(maxWidth: .infinity)
                ItemsSection(
                    candidates: $candidates,
                    selection: $selection,
                    sortOrder: $sortOrder,
                    searchText: $searchText,
                    allowRecopy: $allowRecopy,
                    measuringIDs: measuringIDs,
                    fileNamesByID: fileNamesByID,
                    previouslyCopiedIDs: previouslyCopiedIDs,
                    copyHistoryLookup: { id in copyHistory.entry(for: id) },
                    isExporting: isExporting,
                    selectedCount: selection.count,
                    selectedBytes: selectedTotalBytes
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ActionsFooter(
                canExport: canExport,
                isMeasuring: isMeasuring && !selection.isEmpty,
                onSaveHTML: saveHTMLReport,
                onCreateBundle: { showingBundleSheet = true }
            )
            StatusBar(
                message: statusMessage,
                isExporting: isExporting,
                errorMessage: scanError
            )
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            copyHistory = CopyHistoryStore.load()
            await measureMediaFoldersInitial()
            await loadHomebrew()
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveScannerResetWindowSize)) { _ in
            NSApp.keyWindow?.setContentSize(NSSize(width: 1280, height: 800))
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveScannerClearCopyHistoryRequested)) { _ in
            showingClearHistoryAlert = true
        }
        .sheet(isPresented: $showingBundleSheet) {
            BundleSheet(
                defaultBundleName: BundleBuilder.defaultBundleName(userContext: currentUserContext()),
                onCancel: { showingBundleSheet = false },
                onCreate: { config in
                    showingBundleSheet = false
                    Task { @MainActor in await performBundle(config: config) }
                }
            )
        }
        .sheet(isPresented: $showingBrewDetail) {
            if let info = homebrewInfo, !info.isEmpty {
                HomebrewDetailSheet(info: info, onDismiss: { showingBrewDetail = false })
            }
        }
        .alert("Clear copy history?", isPresented: $showingClearHistoryAlert) {
            Button("Clear", role: .destructive) {
                CopyHistoryStore.clear()
                copyHistory = CopiedHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the record of \(copyHistory.entries.count) previously-copied item(s). They will become tickable again on the next scan.")
        }
    }

    // MARK: - Scan + measurement

    @MainActor
    private func runScan() async {
        scanError = nil
        isScanning = true
        statusMessage = ""
        fileNamesByID = [:]
        measuringIDs = []
        defer { isScanning = false }
        do {
            let result = try HomeScanner.scan()
            candidates = result.candidates.map { $0.isDirectory && !$0.isSymlink ? $0.with(sizeBytes: 0) : $0 }
            topLevelFolders = result.topLevelFolders
            selection = []
            measuringIDs = Set(candidates.filter { $0.isDirectory && !$0.isSymlink }.map(\.id))
            let projects = candidates.filter { $0.category == .codeProject }.count
            let configs = candidates.filter { $0.category == .devConfig }.count
            let previouslyCopiedCount = candidates.filter { previouslyCopiedIDs.contains($0.id) }.count
            var msg = "Found \(candidates.count) items in \(topLevelFolders.count) top-level folders — \(projects) projects, \(configs) dev configs."
            if previouslyCopiedCount > 0 {
                msg += " \(previouslyCopiedCount) already migrated."
            }
            msg += " Measuring sizes…"
            statusMessage = msg
            startSizeMeasurements()
        } catch {
            scanError = error.localizedDescription
            candidates = []
            topLevelFolders = []
            selection = []
            measuringIDs = []
        }
        await measureMediaFoldersInitial()
        if homebrewInfo == nil {
            await loadHomebrew()
        }
    }

    private func startSizeMeasurements() {
        let toMeasure = candidates.filter { $0.isDirectory && !$0.isSymlink }
        for item in toMeasure {
            let id = item.id
            let url = item.url
            Task.detached(priority: .userInitiated) {
                let result = HomeScanner.measureDirectory(url)
                await MainActor.run {
                    applyMeasurement(id: id, measurement: result)
                }
            }
        }
    }

    @MainActor
    private func applyMeasurement(id: CandidateItem.ID, measurement: DirectoryMeasurement) {
        if let idx = candidates.firstIndex(where: { $0.id == id }) {
            candidates[idx] = candidates[idx].with(sizeBytes: measurement.totalBytes)
            candidates.sort(using: sortOrder)
        }
        fileNamesByID[id] = measurement.fileNames
        measuringIDs.remove(id)

        let lookup = candidatesByID
        var touched = false
        for (fIdx, folder) in topLevelFolders.enumerated() where folder.childIDs.contains(id) {
            let newSize = folder.childIDs.reduce(Int64(0)) { sum, cid in sum + (lookup[cid]?.sizeBytes ?? 0) }
            if newSize != folder.sizeBytes {
                topLevelFolders[fIdx].sizeBytes = newSize
                touched = true
            }
        }
        if touched {
            topLevelFolders.sort(using: topLevelSortOrder)
        }

        if measuringIDs.isEmpty {
            statusMessage = "Sizes measured. \(candidates.count) items ready."
        }
    }

    @MainActor
    private func measureMediaFoldersInitial() async {
        for folder in MediaFolder.allCases {
            mediaLoading.insert(folder)
        }
        for folder in MediaFolder.allCases {
            let m = await HomeScanner.measureMediaFolder(folder)
            mediaMeasurements[folder] = m
            mediaLoading.remove(folder)
        }
    }

    @MainActor
    private func loadHomebrew() async {
        brewLoading = true
        defer { brewLoading = false }
        homebrewInfo = await HomebrewService.enumerate()
    }

    // MARK: - Export helpers

    private func currentUserContext() -> UserContext {
        UserContext(
            fullName: NSFullUserName(),
            shortName: NSUserName(),
            hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private func buildFileIndex(for items: [CandidateItem]) -> [String: [String]] {
        let homePath = NSHomeDirectory()
        var index: [String: [String]] = [:]
        for item in items {
            guard let names = fileNamesByID[item.id], !names.isEmpty else { continue }
            let key: String
            if item.url.path.hasPrefix(homePath) {
                let rel = String(item.url.path.dropFirst(homePath.count))
                key = "~" + (rel.hasPrefix("/") ? rel : "/" + rel)
            } else {
                key = item.url.path
            }
            index[key] = names
        }
        return index
    }

    private func buildCurrentHtmlPair(
        selected: [CandidateItem],
        excluded: [CandidateItem],
        userContext: UserContext,
        inventoryLinkHref: String,
        searchLinkHref: String
    ) throws -> (inventory: String, fileSearch: String) {
        let rollup = try HomeScanner.buildFolderRollup(forSelectedURLs: selected.map(\.url))
        let mediaList = MediaFolder.allCases.compactMap { mediaMeasurements[$0] }
        let fileIndex = buildFileIndex(for: selected)
        let inventory = HTMLReportBuilder.buildReport(
            userContext: userContext,
            selectedItems: selected,
            excludedItems: excluded,
            rollup: rollup,
            mediaMeasurements: mediaList,
            homebrew: homebrewInfo,
            searchLinkHref: fileIndex.isEmpty ? nil : searchLinkHref
        )
        let fileSearch = FileSearchHTMLBuilder.buildSearchPage(
            userContext: userContext,
            fileIndex: fileIndex,
            inventoryLinkHref: inventoryLinkHref
        )
        return (inventory, fileSearch)
    }

    private func exportProgressStep(_ p: ExportProgress) -> Int {
        guard p.totalCount > 0 else { return 0 }
        return min(p.completedCount + 1, p.totalCount)
    }

    // MARK: - HTML save

    private func saveHTMLReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "DriveScanner-migration-report.html"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await performHTMLExport(to: url)
            }
        }
    }

    @MainActor
    private func performHTMLExport(to url: URL) async {
        isExporting = true
        statusMessage = "Building HTML…"
        defer { isExporting = false }
        do {
            let selectedItems = candidates.filter { selection.contains($0.id) }
            let excludedItems = candidates.filter { !selection.contains($0.id) }
            let baseName = url.deletingPathExtension().lastPathComponent
            let parent = url.deletingLastPathComponent()
            let searchURL = parent.appendingPathComponent("\(baseName)-search.html")
            let pair = try buildCurrentHtmlPair(
                selected: selectedItems,
                excluded: excludedItems,
                userContext: currentUserContext(),
                inventoryLinkHref: url.lastPathComponent,
                searchLinkHref: searchURL.lastPathComponent
            )
            try pair.inventory.write(to: url, atomically: true, encoding: .utf8)
            if !buildFileIndex(for: selectedItems).isEmpty {
                try pair.fileSearch.write(to: searchURL, atomically: true, encoding: .utf8)
                statusMessage = "Saved \(url.lastPathComponent) and \(searchURL.lastPathComponent) to \(parent.path)"
            } else {
                statusMessage = "Saved report to \(url.path)"
            }
        } catch {
            statusMessage = "HTML export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Bundle

    @MainActor
    private func performBundle(config: BundleSheetConfig) async {
        isExporting = true
        statusMessage = "Preparing bundle…"
        defer { isExporting = false }

        let selectedItems = candidates.filter { selection.contains($0.id) }
        let excludedItems = candidates.filter { !selection.contains($0.id) }
        let userContext = currentUserContext()
        let homeURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let fm = FileManager.default

        let workingDir: URL
        let isTemp: Bool
        if config.format == .folder {
            workingDir = config.destinationDirectory.appendingPathComponent(config.bundleName, isDirectory: true)
            isTemp = false
        } else {
            workingDir = fm.temporaryDirectory
                .appendingPathComponent("DriveScannerBundle-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent(config.bundleName, isDirectory: true)
            isTemp = true
        }

        do {
            let pair = try buildCurrentHtmlPair(
                selected: selectedItems,
                excluded: excludedItems,
                userContext: userContext,
                inventoryLinkHref: "inventory.html",
                searchLinkHref: "file-search.html"
            )
            let brewfile = (homebrewInfo?.isEmpty == false) ? homebrewInfo?.brewfile : nil
            let hasFileSearch = !buildFileIndex(for: selectedItems).isEmpty

            statusMessage = "Copying \(selectedItems.count) items…"
            let result = try await BundleBuilder.build(
                bundleURL: workingDir,
                selectedItems: selectedItems,
                homeURL: homeURL,
                userContext: userContext,
                htmlReport: pair.inventory,
                fileSearchHtml: hasFileSearch ? pair.fileSearch : nil,
                brewfile: brewfile
            ) { progress in
                Task { @MainActor in
                    let step = exportProgressStep(progress)
                    if progress.currentPath.isEmpty {
                        statusMessage = "Finalising bundle…"
                    } else {
                        let name = (progress.currentPath as NSString).lastPathComponent
                        statusMessage = "Copying \(step)/\(progress.totalCount): \(name)"
                    }
                }
            }

            switch config.format {
            case .folder:
                statusMessage = "Bundle ready at \(result.bundleURL.path) (\(result.copiedCount) copied, \(result.skippedCount) skipped) · inventory.html included"
            case .targz:
                let outURL = config.destinationDirectory.appendingPathComponent("\(config.bundleName).tar.gz")
                statusMessage = "Creating tar.gz…"
                try await ArchiveService.createTarGz(bundleDir: workingDir, outputArchive: outURL)
                statusMessage = "Bundle ready at \(outURL.path) · inventory.html included"
            case .encryptedDmg:
                let outURL = config.destinationDirectory.appendingPathComponent("\(config.bundleName).dmg")
                let volumeName = ArchiveService.sanitizedVolumeName(config.bundleName)
                statusMessage = "Creating encrypted DMG (this can take a while)…"
                try await ArchiveService.createEncryptedDmg(
                    bundleDir: workingDir,
                    outputDmg: outURL,
                    volumeName: volumeName,
                    password: config.password
                )
                statusMessage = "Encrypted DMG ready at \(outURL.path) · inventory.html included"
            }

            // Record successfully-copied items in the persistent history.
            let updated = CopyHistoryStore.append(
                items: selectedItems,
                bundleName: config.bundleName,
                to: copyHistory
            )
            try? CopyHistoryStore.save(updated)
            copyHistory = updated

            if isTemp {
                let tempRoot = workingDir.deletingLastPathComponent()
                try? fm.removeItem(at: tempRoot)
            }
        } catch {
            statusMessage = "Bundle failed: \(error.localizedDescription)"
            if isTemp {
                let tempRoot = workingDir.deletingLastPathComponent()
                try? fm.removeItem(at: tempRoot)
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1280, height: 800)
}
