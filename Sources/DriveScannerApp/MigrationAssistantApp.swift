import AppKit
import DriveScannerUI
import SwiftUI

@main
struct MigrationAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Reset Window Size") {
                    NotificationCenter.default.post(name: .driveScannerResetWindowSize, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
            CommandMenu("History") {
                Button("Clear Copy History…") {
                    NotificationCenter.default.post(name: .driveScannerClearCopyHistoryRequested, object: nil)
                }
            }
        }
    }
}
