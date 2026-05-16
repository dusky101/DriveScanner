import SwiftUI

struct ActionsFooter: View {
    let canExport: Bool
    let isMeasuring: Bool
    let onSaveHTML: () -> Void
    let onCreateBundle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isMeasuring {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for size measurement to finish…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onSaveHTML) {
                Label("Save HTML report…", systemImage: "doc.richtext")
            }
            .controlSize(.large)
            .disabled(!canExport)

            Button(action: onCreateBundle) {
                Label("Create migration bundle…", systemImage: "shippingbox.fill")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!canExport)
        }
    }
}

struct StatusBar: View {
    let message: String
    let isExporting: Bool
    let errorMessage: String?

    var body: some View {
        if let err = errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
        } else if isExporting || !message.isEmpty {
            HStack(spacing: 8) {
                if isExporting {
                    ProgressView().controlSize(.small)
                } else if !message.isEmpty {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
        }
    }
}
