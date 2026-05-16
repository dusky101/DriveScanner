import SwiftUI
import DriveScannerCore

// MARK: - Card surface

struct CardStyle: ViewModifier {
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
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16, cornerRadius: CGFloat = 12) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var count: Int? = nil
    var accent: Color = .accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    if let count {
                        Text("\(count)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pill-style label

struct PillLabel: View {
    let label: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color)
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

// MARK: - Category colours & icons

extension CandidateCategory {
    var swatch: Color {
        switch self {
        case .codeProject:  return Color(red: 0.10, green: 0.62, blue: 0.34)
        case .personalData: return Color(red: 0.04, green: 0.50, blue: 0.96)
        case .devConfig:    return Color(red: 0.56, green: 0.27, blue: 0.68)
        case .looseFile:    return Color.secondary
        }
    }

    var iconName: String {
        switch self {
        case .codeProject:  return "chevron.left.forwardslash.chevron.right"
        case .personalData: return "folder.fill"
        case .devConfig:    return "gearshape.fill"
        case .looseFile:    return "doc"
        }
    }
}

// MARK: - Metric tile

struct MetricCard: View {
    let label: String
    let icon: String
    let value: String
    var subtitle: String? = nil
    var isLoading: Bool = false
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 2)
            } else {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Helpers

enum PathFormat {
    static func tildeHome(_ url: URL) -> String {
        let home = NSHomeDirectory()
        let p = url.path
        if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
        return p
    }
}
