import AppKit
import SwiftUI

@main
struct MigrationAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
        }
    }
}
