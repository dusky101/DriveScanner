import DriveScannerCore
import SwiftUI

struct ItemsSection: View {
    @Binding var candidates: [CandidateItem]
    @Binding var selection: Set<CandidateItem.ID>
    @Binding var sortOrder: [KeyPathComparator<CandidateItem>]
    @Binding var searchText: String
    let measuringIDs: Set<CandidateItem.ID>
    let fileNamesByID: [CandidateItem.ID: [String]]
    let isExporting: Bool

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                icon: "doc.on.doc.fill",
                title: "Items to migrate",
                subtitle: subtitle,
                count: candidates.isEmpty ? nil : visibleCandidates.count,
                accent: Color(red: 0.10, green: 0.62, blue: 0.34)
            )
            searchAndActions
            content
        }
        .card()
    }

    private var subtitle: String {
        if !searchText.isEmpty {
            return "Search matches folder names and any file inside"
        }
        return "Includes expanded projects and developer configs"
    }

    private var searchAndActions: some View {
        HStack(spacing: 8) {
            SearchField(text: $searchText, placeholder: "Search by folder or any file inside…")
            Button {
                selection.formUnion(visibleCandidates.map(\.id))
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
            }
            .width(28)

            TableColumn("Name", value: \.name) { item in
                ItemNameCell(item: item)
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
        .frame(minHeight: 320)
        .onChange(of: sortOrder) { _, newValue in
            candidates.sort(using: newValue)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.category.iconName)
                    .foregroundStyle(item.category.swatch)
                    .font(.callout)
                Text(item.name)
                    .lineLimit(1)
                if item.isSymlink {
                    PillLabel(label: "symlink", color: .orange)
                }
            }
            HStack(spacing: 4) {
                PillLabel(label: item.category.displayLabel, color: item.category.swatch)
                if let stack = item.stack {
                    PillLabel(label: stack.displayLabel, color: .secondary)
                }
            }
        }
        .padding(.vertical, 1)
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
