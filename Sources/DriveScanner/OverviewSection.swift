import DriveScannerCore
import SwiftUI

struct OverviewSection: View {
    let mediaMeasurements: [MediaFolder: MediaFolderMeasurement]
    let mediaLoading: Set<MediaFolder>
    let homebrewInfo: HomebrewInfo?
    let brewLoading: Bool
    let onOpenHomebrew: () -> Void

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 170, maximum: 320), spacing: 10),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            MetricCard(
                label: "Pictures",
                icon: "photo.fill",
                value: mediaValue(.pictures),
                subtitle: mediaSubtitle(.pictures),
                isLoading: mediaLoading.contains(.pictures),
                accent: Color(red: 0.93, green: 0.36, blue: 0.51)
            )
            MetricCard(
                label: "Music",
                icon: "music.note",
                value: mediaValue(.music),
                subtitle: mediaSubtitle(.music),
                isLoading: mediaLoading.contains(.music),
                accent: Color(red: 0.94, green: 0.31, blue: 0.31)
            )
            MetricCard(
                label: "Movies",
                icon: "film.fill",
                value: mediaValue(.movies),
                subtitle: mediaSubtitle(.movies),
                isLoading: mediaLoading.contains(.movies),
                accent: Color(red: 0.97, green: 0.62, blue: 0.16)
            )
            MetricCard(
                label: "Homebrew",
                icon: "shippingbox.fill",
                value: brewValue,
                subtitle: brewSubtitle,
                isLoading: brewLoading,
                accent: Color(red: 0.74, green: 0.48, blue: 0.30),
                action: brewIsOpenable ? onOpenHomebrew : nil
            )
        }
    }

    private var brewIsOpenable: Bool {
        guard let info = homebrewInfo else { return false }
        return !info.isEmpty
    }

    private func mediaValue(_ folder: MediaFolder) -> String {
        guard let m = mediaMeasurements[folder] else { return "—" }
        return m.exists
            ? ByteCountFormatter.string(fromByteCount: m.totalBytes, countStyle: .file)
            : "Not found"
    }

    private func mediaSubtitle(_ folder: MediaFolder) -> String? {
        guard let m = mediaMeasurements[folder] else { return nil }
        return m.exists ? "~/\(folder.directoryName)" : nil
    }

    private var brewValue: String {
        guard let info = homebrewInfo, !info.isEmpty else { return "—" }
        return "\(info.formulaCount + info.caskCount)"
    }

    private var brewSubtitle: String? {
        guard let info = homebrewInfo else { return "not detected" }
        if info.isEmpty { return "no items" }
        return "\(info.formulaCount) brew · \(info.caskCount) cask · \(info.tapCount) tap"
    }
}
