import Cocoa
import ApplicationServices

/// Permission manager - NOT @Observable to avoid conflicts with SwiftUI observation.
/// Views should maintain their own @State for permission status and call checkAccessibility() to update.
final class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    /// Check if accessibility permission is granted. Call this from main thread.
    func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        // This opens System Settings > Privacy > Accessibility with app highlighted
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
