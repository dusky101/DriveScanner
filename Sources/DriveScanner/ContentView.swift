import AppKit
import DriveScannerCore
import SwiftUI

struct ContentView: View {
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
    @State private var measuringIDs: Set<CandidateItem.ID> = []
    @State private var fileNamesByID: [CandidateItem.ID: [String]] = [:]
    @State private var sortOrder: [KeyPathComparator<CandidateItem>] = [
        .init(\.sizeBytes, order: .reverse)
    ]

    private var candidatesByID: [CandidateItem.ID: CandidateItem] {
        Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
    }

    private var visibleCandidates: [CandidateItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter { item in
            if item.name.lowercased().contains(q) { return true }
            if let names = fileNamesByID[item.id] {
                return names.contains { $0.lowercased().contains(q) }
            }
            return false
        }
    }

    private var selectedURLs: [URL] {
        candidates.filter { selection.contains($0.id) }.map(\.url)
    }

    private var isMeasuring: Bool { !measuringIDs.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Scan my home folder") {
                    Task { await runScan() }
                }
                .disabled(isScanning || isExporting)
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
                if isMeasuring {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Measuring sizes… \(candidates.count - measuringIDs.count)/\(candidates.filter { $0.isDirectory && !$0.isSymlink }.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let scanError {
                Text(scanError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            GroupBox("Standard media folders (total size)") {
                mediaSizesTable
            }

            GroupBox("Homebrew") {
                homebrewSummary
            }

            GroupBox("Top-level folders in your home (\(topLevelFolders.count))") {
                topLevelFoldersTable
            }

            GroupBox("Items outside usual locations") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Search by folder name or any file inside…", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                        Button("Select all visible") {
                            selection.formUnion(visibleCandidates.map(\.id))
                        }
                        .disabled(visibleCandidates.isEmpty || isExporting)
                        Button("Clear visible") {
                            selection.subtract(visibleCandidates.map(\.id))
                        }
                        .disabled(visibleCandidates.isEmpty || isExporting)
                    }
                    Table(visibleCandidates, selection: $selection, sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(item.name)
                                    if item.isSymlink {
                                        chip("symlink", color: .orange)
                                    }
                                }
                                HStack(spacing: 4) {
                                    chip(item.category.displayLabel, color: color(for: item.category))
                                    if let stack = item.stack {
                                        chip(stack.displayLabel, color: .secondary)
                                    }
                                }
                            }
                        }
                        TableColumn("Size", value: \.sizeBytes) { item in
                            if measuringIDs.contains(item.id) {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("measuring…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(byteString(item.sizeBytes))
                            }
                        }
                        TableColumn("Modified", value: \.modificationSortKey) { item in
                            Text(item.modificationDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                        }
                        TableColumn("Path", value: \.url.path) { item in
                            Text(item.url.path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: true))
                    .onChange(of: sortOrder) { _, newValue in
                        candidates.sort(using: newValue)
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Save HTML report…") { saveHTMLReport() }
                    .disabled(selectedURLs.isEmpty || isExporting || isMeasuring)
                Button("Create migration bundle…") { showingBundleSheet = true }
                    .disabled(selectedURLs.isEmpty || isExporting || isMeasuring)
                    .buttonStyle(.borderedProminent)
                if isMeasuring && !selectedURLs.isEmpty {
                    Text("Waiting for size measurement…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isExporting {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .task {
            await measureMediaFoldersInitial()
            await loadHomebrew()
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
    }

    private var topLevelFoldersTable: some View {
        Group {
            if topLevelFolders.isEmpty {
                Text("Scan to populate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Table(topLevelFolders) {
                    TableColumn("") { folder in
                        Toggle("", isOn: bindingFor(folder))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                    }
                    .width(28)
                    TableColumn("Name") { folder in
                        HStack(spacing: 6) {
                            Text(folder.name)
                            if isPartiallySelected(folder) {
                                Text("partial")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.85))
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                    TableColumn("Size") { folder in
                        if isMeasuringFolder(folder) {
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.mini)
                                Text("measuring…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(byteString(topLevelSize(folder)))
                                .font(.system(.body, design: .default).monospacedDigit())
                        }
                    }
                    TableColumn("Contains") { folder in
                        Text(folder.childIDs.count == 1 ? "1 item" : "\(folder.childIDs.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Path") { folder in
                        Text(folder.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 160, idealHeight: 220)
            }
        }
    }

    private func bindingFor(_ folder: TopLevelFolder) -> Binding<Bool> {
        Binding(
            get: {
                !folder.childIDs.isEmpty && folder.childIDs.allSatisfy { self.selection.contains($0) }
            },
            set: { newValue in
                if newValue {
                    self.selection.formUnion(folder.childIDs)
                } else {
                    self.selection.subtract(folder.childIDs)
                }
            }
        )
    }

    private func isPartiallySelected(_ folder: TopLevelFolder) -> Bool {
        guard !folder.childIDs.isEmpty else { return false }
        let count = folder.childIDs.reduce(0) { $0 + (selection.contains($1) ? 1 : 0) }
        return count > 0 && count < folder.childIDs.count
    }

    private func isMeasuringFolder(_ folder: TopLevelFolder) -> Bool {
        folder.childIDs.contains { measuringIDs.contains($0) }
    }

    private func topLevelSize(_ folder: TopLevelFolder) -> Int64 {
        let lookup = candidatesByID
        return folder.childIDs.reduce(Int64(0)) { sum, id in sum + (lookup[id]?.sizeBytes ?? 0) }
    }

    private var mediaSizesTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(MediaFolder.allCases, id: \.self) { folder in
                GridRow {
                    Text(folder.displayLabel)
                        .frame(width: 160, alignment: .leading)
                    if mediaLoading.contains(folder) {
                        ProgressView()
                            .controlSize(.small)
                    } else if let m = mediaMeasurements[folder] {
                        if m.exists {
                            Text("\(byteString(m.totalBytes)) (\(m.totalBytes) bytes)")
                        } else {
                            Text("Not found")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var homebrewSummary: some View {
        HStack(spacing: 16) {
            if brewLoading {
                ProgressView().controlSize(.small)
                Text("Reading brew bundle…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let info = homebrewInfo, !info.isEmpty {
                Text("\(info.formulaCount) formulae, \(info.caskCount) casks, \(info.tapCount) taps")
                    .font(.callout)
                if info.masCount > 0 {
                    Text("+ \(info.masCount) Mac App Store")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(info.brewPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Homebrew not detected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func color(for category: CandidateCategory) -> Color {
        switch category {
        case .codeProject: return .green
        case .personalData: return .blue
        case .devConfig: return .purple
        case .looseFile: return .gray
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
            // Reset directory sizes to 0; recursive pass will fill them in.
            candidates = result.candidates.map { $0.isDirectory && !$0.isSymlink ? $0.with(sizeBytes: 0) : $0 }
            topLevelFolders = result.topLevelFolders
            selection = []
            measuringIDs = Set(candidates.filter { $0.isDirectory && !$0.isSymlink }.map(\.id))
            let projects = candidates.filter { $0.category == .codeProject }.count
            let configs = candidates.filter { $0.category == .devConfig }.count
            statusMessage = "Found \(candidates.count) item(s) under \(topLevelFolders.count) top-level folder(s) — \(projects) projects, \(configs) dev configs. Measuring sizes…"
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

    /// Kicks off a parallel recursive measurement for every directory candidate.
    /// Updates `candidates` and `fileNamesByID` as each completes; clears `measuringIDs` when done.
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
        if measuringIDs.isEmpty {
            statusMessage = "Sizes measured. \(candidates.count) item(s) ready."
        }
    }

    private func exportProgressStep(_ p: ExportProgress) -> Int {
        guard p.totalCount > 0 else { return 0 }
        return min(p.completedCount + 1, p.totalCount)
    }

    private func byteString(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = .useAll
        f.countStyle = .file
        return f.string(fromByteCount: n)
    }

    private func currentUserContext() -> UserContext {
        UserContext(
            fullName: NSFullUserName(),
            shortName: NSUserName(),
            hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    /// Builds the file-index dict expected by HTMLReportBuilder: path-under-~/ → leaf file names.
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

    /// Builds both the inventory HTML and the dedicated file-search page. The inventory carries
    /// a link to `searchLinkHref` (which the caller chooses based on the on-disk file name).
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

            // Compute sibling file-search.html path: "<base>-search.html" next to "<base>.html".
            let baseName = url.deletingPathExtension().lastPathComponent
            let parent = url.deletingLastPathComponent()
            let searchURL = parent.appendingPathComponent("\(baseName)-search.html")
            let inventoryHref = url.lastPathComponent
            let searchHref = searchURL.lastPathComponent

            let pair = try buildCurrentHtmlPair(
                selected: selectedItems,
                excluded: excludedItems,
                userContext: currentUserContext(),
                inventoryLinkHref: inventoryHref,
                searchLinkHref: searchHref
            )
            try pair.inventory.write(to: url, atomically: true, encoding: .utf8)
            // Only write the search page if we have something to index.
            let hasFiles = !buildFileIndex(for: selectedItems).isEmpty
            if hasFiles {
                try pair.fileSearch.write(to: searchURL, atomically: true, encoding: .utf8)
                statusMessage = "Saved \(url.lastPathComponent) and \(searchURL.lastPathComponent) to \(parent.path)"
            } else {
                statusMessage = "Saved report to \(url.path)"
            }
        } catch {
            statusMessage = "HTML export failed: \(error.localizedDescription)"
        }
    }

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

            statusMessage = "Copying \(selectedItems.count) item(s)…"
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
                statusMessage = "Bundle ready at \(result.bundleURL.path) (\(result.copiedCount) copied, \(result.skippedCount) skipped)"

            case .targz:
                let outURL = config.destinationDirectory.appendingPathComponent("\(config.bundleName).tar.gz")
                statusMessage = "Creating tar.gz…"
                try await ArchiveService.createTarGz(bundleDir: workingDir, outputArchive: outURL)
                statusMessage = "Bundle ready at \(outURL.path)"

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
                statusMessage = "Encrypted DMG ready at \(outURL.path)"
            }

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
}
