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
    var action: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        if let action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
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
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent.opacity(isHovered ? 1.0 : 0.45))
                }
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
                .fill(isHovered && action != nil
                      ? Color(nsColor: .controlAccentColor).opacity(0.06)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovered && action != nil
                        ? accent.opacity(0.5)
                        : Color(nsColor: .separatorColor).opacity(0.55),
                        lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
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

// MARK: - Selection summary

/// Compact accent-tinted capsule that shows "N · X GB" — used in section headers.
struct SelectionSummary: View {
    let count: Int
    let sizeBytes: Int64
    var icon: String = "tray.full.fill"

    private var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tint)
            Text("\(count) · \(formattedBytes)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Cross-module commands

public extension Notification.Name {
    static let driveScannerResetWindowSize = Notification.Name("DriveScanner.resetWindowSize")
    static let driveScannerClearCopyHistoryRequested = Notification.Name("DriveScanner.clearCopyHistoryRequested")
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

extension Date {
    /// "Copied 16 May 2026" — short medium-date for the copy history badge.
    var copiedBadgeText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "en_GB")
        return "Copied \(f.string(from: self))"
    }
}
