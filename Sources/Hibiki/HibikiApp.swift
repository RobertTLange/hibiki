import SwiftUI
import KeyboardShortcuts

@main
struct HibikiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppState.shared)
        }
    }
}
