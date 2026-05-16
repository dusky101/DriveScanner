import DriveScannerCore
import SwiftUI

struct TopLevelFoldersSection: View {
    @Binding var folders: [TopLevelFolder]
    @Binding var selection: Set<CandidateItem.ID>
    @Binding var sortOrder: [KeyPathComparator<TopLevelFolder>]
    let measuringIDs: Set<CandidateItem.ID>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                icon: "house.fill",
                title: "Top-level folders in your home",
                subtitle: "Tick a folder to select everything inside",
                count: folders.isEmpty ? nil : folders.count,
                accent: Color(red: 0.04, green: 0.50, blue: 0.96)
            )
            content
        }
        .card()
    }

    @ViewBuilder
    private var content: some View {
        if folders.isEmpty {
            EmptyStateView(icon: "tray", text: "Scan to populate.")
        } else {
            table
        }
    }

    private var table: some View {
        Table(folders, sortOrder: $sortOrder) {
            TableColumn("") { folder in
                Toggle("", isOn: binding(for: folder))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(28)

            TableColumn("Name", value: \.name) { folder in
                TopLevelNameCell(folder: folder, isPartial: isPartiallySelected(folder))
            }

            TableColumn("Size", value: \.sizeBytes) { folder in
                TopLevelSizeCell(
                    sizeBytes: folder.sizeBytes,
                    isMeasuring: isMeasuring(folder)
                )
            }
            .width(min: 100, ideal: 120, max: 150)

            TableColumn("Contains", value: \.childCount) { folder in
                Text("\(folder.childCount) item\(folder.childCount == 1 ? "" : "s")")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 95, max: 130)

            TableColumn("Path", value: \.url.path) { folder in
                Text(PathFormat.tildeHome(folder.url))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 180, idealHeight: 240)
        .onChange(of: sortOrder) { _, newValue in
            folders.sort(using: newValue)
        }
    }

    private func binding(for folder: TopLevelFolder) -> Binding<Bool> {
        Binding(
            get: {
                !folder.childIDs.isEmpty && folder.childIDs.allSatisfy { selection.contains($0) }
            },
            set: { newValue in
                if newValue {
                    selection.formUnion(folder.childIDs)
                } else {
                    selection.subtract(folder.childIDs)
                }
            }
        )
    }

    private func isPartiallySelected(_ folder: TopLevelFolder) -> Bool {
        guard !folder.childIDs.isEmpty else { return false }
        let count = folder.childIDs.reduce(0) { $0 + (selection.contains($1) ? 1 : 0) }
        return count > 0 && count < folder.childIDs.count
    }

    private func isMeasuring(_ folder: TopLevelFolder) -> Bool {
        folder.childIDs.contains { measuringIDs.contains($0) }
    }
}

// MARK: - Cells

private struct TopLevelNameCell: View {
    let folder: TopLevelFolder
    let isPartial: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint.opacity(0.85))
                .font(.callout)
            Text(folder.name)
                .lineLimit(1)
            if isPartial {
                PillLabel(label: "Partial", color: .orange, icon: "checkmark.circle.fill")
            }
        }
    }
}

private struct TopLevelSizeCell: View {
    let sizeBytes: Int64
    let isMeasuring: Bool

    var body: some View {
        if isMeasuring {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("measuring…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                .font(.callout.monospacedDigit())
        }
    }
}
