import DriveScannerCore
import SwiftUI

struct ItemsSection: View {
    @Binding var candidates: [CandidateItem]
    @Binding var selection: Set<CandidateItem.ID>
    @Binding var sortOrder: [KeyPathComparator<CandidateItem>]
    @Binding var searchText: String
    @Binding var allowRecopy: Bool
    let measuringIDs: Set<CandidateItem.ID>
    let fileNamesByID: [CandidateItem.ID: [String]]
    let previouslyCopiedIDs: Set<CandidateItem.ID>
    let copyHistoryLookup: (CandidateItem.ID) -> CopiedEntry?
    let isExporting: Bool
    let selectedCount: Int
    let selectedBytes: Int64

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

    private var copiedCountInVisible: Int {
        visibleCandidates.reduce(0) { $0 + (previouslyCopiedIDs.contains($1.id) ? 1 : 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SectionHeader(
                    icon: "doc.on.doc.fill",
                    title: "Items to migrate",
                    subtitle: subtitle,
                    count: candidates.isEmpty ? nil : visibleCandidates.count,
                    accent: Color(red: 0.10, green: 0.62, blue: 0.34)
                )
                SelectionSummary(count: selectedCount, sizeBytes: selectedBytes)
            }
            searchAndActions
            content
        }
        .card()
        .frame(maxHeight: .infinity)
    }

    private var subtitle: String {
        if !searchText.isEmpty {
            return "Search matches folder names and any file inside"
        }
        if copiedCountInVisible > 0 {
            return "\(copiedCountInVisible) item(s) already migrated — toggle \"Allow re-copy\" to re-include them"
        }
        return "Includes expanded projects and developer configs"
    }

    private var searchAndActions: some View {
        HStack(spacing: 8) {
            SearchField(text: $searchText, placeholder: "Search by folder or any file inside…")
            Button {
                let addable = visibleCandidates
                    .filter { allowRecopy || !previouslyCopiedIDs.contains($0.id) }
                    .map(\.id)
                selection.formUnion(addable)
            } label: {
                Label("Select visible", systemImage: "checkmark.circle")
            }
            .disabled(visibleCandidates.isEmpty || isExporting)
            Button {
                selection.subtract(visibleCandidates.map(\.id))
            } label: {
                Label("Clear visible", systemImage: "circle")
            }
            .disabled(visibleCandidates.isEmpty || isExporting)
            Toggle(isOn: $allowRecopy) {
                Label("Allow re-copy", systemImage: "arrow.uturn.backward.circle")
            }
            .toggleStyle(.button)
            .help("When on, items previously copied can be ticked again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if candidates.isEmpty {
            EmptyStateView(icon: "magnifyingglass", text: "Scan to populate.")
        } else {
            table
        }
    }

    private var table: some View {
        Table(visibleCandidates, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("", isOn: binding(for: item))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(isDisabled(item))
            }
            .width(28)

            TableColumn("Name", value: \.name) { item in
                ItemNameCell(
                    item: item,
                    wasCopied: previouslyCopiedIDs.contains(item.id),
                    copiedAt: copyHistoryLookup(item.id)?.copiedAt
                )
            }

            TableColumn("Size", value: \.sizeBytes) { item in
                ItemSizeCell(
                    sizeBytes: item.sizeBytes,
                    isMeasuring: measuringIDs.contains(item.id)
                )
            }
            .width(min: 100, ideal: 120, max: 150)

            TableColumn("Modified", value: \.modificationSortKey) { item in
                Text(item.modificationDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 150, max: 200)

            TableColumn("Path", value: \.url.path) { item in
                Text(PathFormat.tildeHome(item.url))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 200, maxHeight: .infinity)
        .onChange(of: sortOrder) { _, newValue in
            candidates.sort(using: newValue)
        }
    }

    private func isDisabled(_ item: CandidateItem) -> Bool {
        previouslyCopiedIDs.contains(item.id) && !allowRecopy
    }

    private func binding(for item: CandidateItem) -> Binding<Bool> {
        Binding(
            get: { selection.contains(item.id) },
            set: { newValue in
                if newValue {
                    selection.insert(item.id)
                } else {
                    selection.remove(item.id)
                }
            }
        )
    }
}

// MARK: - Cells

private struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }
}

private struct ItemNameCell: View {
    let item: CandidateItem
    let wasCopied: Bool
    let copiedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.category.iconName)
                    .foregroundStyle(wasCopied ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(item.category.swatch))
                    .font(.callout)
                Text(item.name)
                    .lineLimit(1)
                    .strikethrough(wasCopied, color: .secondary)
                    .foregroundStyle(wasCopied ? .secondary : .primary)
                if item.isSymlink {
                    PillLabel(label: "symlink", color: .orange)
                }
            }
            HStack(spacing: 4) {
                PillLabel(label: item.category.displayLabel, color: item.category.swatch)
                if let stack = item.stack {
                    PillLabel(label: stack.displayLabel, color: .secondary)
                }
                if wasCopied, let at = copiedAt {
                    PillLabel(label: at.copiedBadgeText, color: .gray, icon: "checkmark.seal.fill")
                } else if wasCopied {
                    PillLabel(label: "Copied", color: .gray, icon: "checkmark.seal.fill")
                }
            }
        }
        .padding(.vertical, 1)
        .opacity(wasCopied ? 0.75 : 1.0)
    }
}

private struct ItemSizeCell: View {
    let sizeBytes: Int64
    let isMeasuring: Bool

    var body: some View {
        if isMeasuring {
            HStack(spacing: 4) {
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
