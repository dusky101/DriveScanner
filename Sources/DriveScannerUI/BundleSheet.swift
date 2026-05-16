import AppKit
import DriveScannerCore
import SwiftUI

struct BundleSheetConfig {
    let format: BundleFormat
    let destinationDirectory: URL
    let bundleName: String
    let password: String
}

struct BundleSheet: View {
    let defaultBundleName: String
    let onCancel: () -> Void
    let onCreate: (BundleSheetConfig) -> Void

    @State private var format: BundleFormat = .encryptedDmg
    @State private var bundleName: String
    @State private var destination: URL?
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    init(defaultBundleName: String, onCancel: @escaping () -> Void, onCreate: @escaping (BundleSheetConfig) -> Void) {
        self.defaultBundleName = defaultBundleName
        self.onCancel = onCancel
        self.onCreate = onCreate
        _bundleName = State(initialValue: defaultBundleName)
    }

    private var passwordsValid: Bool {
        password.count >= 6 && password == confirmPassword
    }

    private var isReady: Bool {
        guard destination != nil else { return false }
        guard !bundleName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if format == .encryptedDmg { return passwordsValid }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create migration bundle")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Text("Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $format) {
                    ForEach(BundleFormat.allCases) { f in
                        Text(f.displayLabel).tag(f)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Bundle name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("DriveScanner-bundle", text: $bundleName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(destination?.path ?? "Choose a destination folder…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(destination == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { pickDestination() }
                }
            }

            if format == .encryptedDmg {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password (at least 6 characters)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Confirm password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                    if !password.isEmpty && password != confirmPassword {
                        Text("Passwords don't match")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if !password.isEmpty && password.count < 6 {
                        Text("Password must be at least 6 characters")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("This password decrypts the DMG. Share it with the user via a separate channel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard let dest = destination else { return }
                    onCreate(BundleSheetConfig(
                        format: format,
                        destinationDirectory: dest,
                        bundleName: bundleName.trimmingCharacters(in: .whitespaces),
                        password: password
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isReady)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose destination folder"
        if panel.runModal() == .OK {
            destination = panel.url
        }
    }
}
