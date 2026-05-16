import AppKit
import DriveScannerCore
import SwiftUI

struct HomebrewDetailSheet: View {
    let info: HomebrewInfo
    let onDismiss: () -> Void

    @State private var lastCopied: String?

    private var summary: String {
        var parts: [String] = []
        if info.formulaCount > 0 { parts.append("\(info.formulaCount) formulae") }
        if info.caskCount > 0    { parts.append("\(info.caskCount) casks") }
        if info.tapCount > 0     { parts.append("\(info.tapCount) taps") }
        if info.masCount > 0     { parts.append("\(info.masCount) Mac App Store apps") }
        return parts.joined(separator: " · ")
    }

    /// One-liner using a heredoc so the user pastes a single command instead of saving a file.
    /// Requires Homebrew to already be installed on the target Mac.
    private var oneLineCommand: String {
        let trimmed = info.brewfile.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        brew bundle --file=- <<'BREWFILE'
        \(trimmed)
        BREWFILE
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            commandCard
            brewfileCard
            footer
        }
        .padding(20)
        .frame(width: 720, height: 660)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(brewAccent.opacity(0.18))
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(brewAccent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Homebrew restore")
                    .font(.title3.weight(.semibold))
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var commandCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("One-line restore command")
                        .font(.headline)
                    Text("Paste into Terminal on the new Mac. Homebrew must already be installed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                copyButton(text: oneLineCommand, key: "command", label: "Copy command", prominent: true)
            }
            codeBlock(text: oneLineCommand, maxHeight: 180)
        }
        .card()
    }

    private var brewfileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Brewfile contents")
                        .font(.headline)
                    Text("Or save this as a file named Brewfile and run: brew bundle --file=Brewfile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                copyButton(text: info.brewfile, key: "brewfile", label: "Copy Brewfile")
            }
            codeBlock(text: info.brewfile, maxHeight: 220)
        }
        .card()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.tertiary)
                .font(.caption)
            Text("Detected at \(info.brewPath)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Spacer()
            Button("Done", action: onDismiss)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Helpers

    private func codeBlock(text: String, maxHeight: CGFloat) -> some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func copyButton(text: String, key: String, label: String, prominent: Bool = false) -> some View {
        let copied = lastCopied == key
        let inner = Button {
            copy(text, key: key)
        } label: {
            Label(copied ? "Copied!" : label, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        if prominent {
            inner.buttonStyle(.borderedProminent)
        } else {
            inner.buttonStyle(.bordered)
        }
    }

    private func copy(_ text: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastCopied = key
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if lastCopied == key { lastCopied = nil }
        }
    }

    private var brewAccent: Color {
        Color(red: 0.74, green: 0.48, blue: 0.30)
    }
}
