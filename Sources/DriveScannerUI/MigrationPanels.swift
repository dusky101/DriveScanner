import SwiftUI

// MARK: - Panel card style
//
// Used by the two side panels (top-level folders, items to migrate).
// Distinct from `CardStyle` in DesignSystem.swift: no outline, soft shadow.
// Keep all the per-panel visual tweaks in this file so they're easy to find.

struct PanelCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }
}

extension View {
    /// Apply the side-panel card treatment: borderless, soft shadow.
    func panelCard(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        modifier(PanelCardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Panel hint
//
// One-line tip row used to balance the two header cards visually. The items
// header has a search + button row; the top-level header gets a PanelHint
// in the same slot so both headers end up the same height.

struct PanelHint: View {
    let text: String
    var icon: String = "info.circle.fill"
    var iconColor: Color = .accentColor

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(iconColor)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconColor.opacity(0.10))
        )
    }
}
