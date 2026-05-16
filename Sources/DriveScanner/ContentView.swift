import AppKit
import DriveScannerCore
import SwiftUI

struct ContentView: View {
    @State private var candidates: [CandidateItem] = []
    @State private var selection: Set<CandidateItem.ID> = []
    @State private var searchText = ""
    @State private var scanError: String?
    @State private var isScanning = false
    @State private var mediaMeasurements: [MediaFolder: MediaFolderMeasurement] = [:]
    @State private var mediaLoading: Set<MediaFolder> = Set(MediaFolder.allCases)
    @State private var statusMessage = ""
    @State private var isExporting = false

    private var visibleCandidates: [CandidateItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return candidates }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var selectedURLs: [URL] {
        candidates.filter { selection.contains($0.id) }.map(\.url)
    }

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

            GroupBox("Items outside usual locations") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Filter by name", text: $searchText)
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
                    Table(visibleCandidates, selection: $selection) {
                        TableColumn("Name") { item in
                            HStack(spacing: 6) {
                                Text(item.name)
                                if item.isSymlink {
                                    Text("symlink")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                        TableColumn("Size") { item in
                            Text(byteString(item.sizeBytes))
                        }
                        TableColumn("Modified") { item in
                            Text(item.modificationDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                        }
                        TableColumn("Path") { item in
                            Text(item.url.path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: true))
                }
            }

            HStack(spacing: 10) {
                Button("Save HTML report…") { saveHTMLReport() }
                    .disabled(selectedURLs.isEmpty || isExporting)
                Button("Copy selected to…") { copySelected() }
                    .disabled(selectedURLs.isEmpty || isExporting)
                Button("Zip selected…") { zipSelected() }
                    .disabled(selectedURLs.isEmpty || isExporting)
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
        }
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
    private func runScan() async {
        scanError = nil
        isScanning = true
        statusMessage = ""
        defer { isScanning = false }
        do {
            let next = try HomeScanner.scanCandidates()
            candidates = next
            selection = []
            statusMessage = "Found \(next.count) top-level item(s)."
        } catch {
            scanError = error.localizedDescription
            candidates = []
            selection = []
        }
        await measureMediaFoldersInitial()
    }

    /// Maps `ExportProgress.completedCount` (0-based index while working) to a 1-based step capped at `totalCount` so the final callback never shows `total+1`.
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
        defer {
            isExporting = false
        }
        do {
            let rollup = try HomeScanner.buildFolderRollup(forSelectedURLs: selectedURLs)
            let selectedItems = candidates.filter { selection.contains($0.id) }
            let userContext = UserContext(
                fullName: NSFullUserName(),
                shortName: NSUserName(),
                hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString
            )
            let mediaList = MediaFolder.allCases.compactMap { mediaMeasurements[$0] }
            let html = HTMLReportBuilder.buildReport(
                userContext: userContext,
                selectedItems: selectedItems,
                allCandidatesCount: candidates.count,
                rollup: rollup,
                mediaMeasurements: mediaList
            )
            try html.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Saved report to \(url.path)"
        } catch {
            statusMessage = "HTML export failed: \(error.localizedDescription)"
        }
    }

    private func copySelected() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose destination folder"
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            Task { @MainActor in
                await performCopy(to: dest)
            }
        }
    }

    @MainActor
    private func performCopy(to dest: URL) async {
        isExporting = true
        statusMessage = "Copying…"
        defer { isExporting = false }
        do {
            try await ExportService.copyItems(selectedURLs, to: dest) { p in
                Task { @MainActor in
                    let step = exportProgressStep(p)
                    statusMessage = "Copying \(step)/\(p.totalCount): \(p.currentPath)"
                }
            }
            statusMessage = "Copied \(selectedURLs.count) item(s) to \(dest.path)"
        } catch {
            statusMessage = "Copy failed: \(error.localizedDescription)"
        }
    }

    private func zipSelected() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "DriveScanner-selection.zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await performZip(to: url)
            }
        }
    }

    @MainActor
    private func performZip(to url: URL) async {
        isExporting = true
        statusMessage = "Zipping with ditto…"
        defer { isExporting = false }
        do {
            try await ExportService.zipItems(selectedURLs, to: url) { p in
                Task { @MainActor in
                    let step = exportProgressStep(p)
                    statusMessage = "Zipping \(step)/\(p.totalCount): \(p.currentPath)"
                }
            }
            statusMessage = "Created \(url.path)"
        } catch {
            statusMessage = "Zip failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
