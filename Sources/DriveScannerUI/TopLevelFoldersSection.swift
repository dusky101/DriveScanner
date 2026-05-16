import DriveScannerCore
import SwiftUI

struct TopLevelFoldersSection: View {
    @Binding var folders: [TopLevelFolder]
    @Binding var selection: Set<CandidateItem.ID>
    @Binding var sortOrder: [KeyPathComparator<TopLevelFolder>]
    let measuringIDs: Set<CandidateItem.ID>
    let previouslyCopiedIDs: Set<CandidateItem.ID>
    let allowRecopy: Bool
    let selectedCount: Int
    let selectedBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SectionHeader(
                    icon: "house.fill",
                    title: "Top-level folders",
                    subtitle: "Tick to cascade · partial when only some children selected",
                    count: folders.isEmpty ? nil : folders.count,
                    accent: Color(red: 0.04, green: 0.50, blue: 0.96)
                )
                SelectionSummary(count: selectedCount, sizeBytes: selectedBytes)
            }
            content
        }
        .card()
        .frame(maxHeight: .infinity)
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
                    .disabled(selectableChildIDs(of: folder).isEmpty)
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
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 200, maxHeight: .infinity)
        .onChange(of: sortOrder) { _, newValue in
            folders.sort(using: newValue)
        }
    }

    /// Children we're allowed to add to selection — excludes previously-copied items when re-copy is off.
    private func selectableChildIDs(of folder: TopLevelFolder) -> [CandidateItem.ID] {
        folder.childIDs.filter { id in
            allowRecopy || !previouslyCopiedIDs.contains(id)
        }
    }

    private func binding(for folder: TopLevelFolder) -> Binding<Bool> {
        Binding(
            get: {
                let allowed = selectableChildIDs(of: folder)
                return !allowed.isEmpty && allowed.allSatisfy { selection.contains($0) }
            },
            set: { newValue in
                let allowed = selectableChildIDs(of: folder)
                if newValue {
                    selection.formUnion(allowed)
                } else {
                    selection.subtract(allowed)
                }
            }
        )
    }

    private func isPartiallySelected(_ folder: TopLevelFolder) -> Bool {
        let allowed = selectableChildIDs(of: folder)
        guard !allowed.isEmpty else { return false }
        let count = allowed.reduce(0) { $0 + (selection.contains($1) ? 1 : 0) }
        return count > 0 && count < allowed.count
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
