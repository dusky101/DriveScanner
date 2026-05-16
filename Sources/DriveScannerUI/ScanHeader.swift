import DriveScannerCore
import SwiftUI

struct ScanHeader: View {
    let userContext: UserContext
    let hasScanned: Bool
    let isScanning: Bool
    let isExporting: Bool
    let measurementProgress: (done: Int, total: Int)?
    let onScan: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text("DriveScanner")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(subline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            measurementBadge
            scanButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.50, blue: 0.96),
                            Color(red: 0.37, green: 0.36, blue: 0.90),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
            Text(userContext.initials)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var measurementBadge: some View {
        if let p = measurementProgress {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Measuring \(p.done)/\(p.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )
        }
    }

    private var scanButton: some View {
        Button(action: onScan) {
            HStack(spacing: 6) {
                if isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: hasScanned ? "arrow.clockwise" : "magnifyingglass")
                }
                Text(hasScanned ? "Re-scan" : "Scan home folder")
            }
            .padding(.horizontal, 6)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(isScanning || isExporting)
    }

    private var subline: String {
        let fullName = userContext.fullName.isEmpty ? userContext.shortName : userContext.fullName
        return "\(fullName) — \(userContext.shortName)@\(userContext.hostName)"
    }
}
