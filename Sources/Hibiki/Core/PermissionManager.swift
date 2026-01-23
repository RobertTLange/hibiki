import Cocoa
import ApplicationServices

@Observable
final class PermissionManager {
    static let shared = PermissionManager()

    var hasAccessibilityPermission = false

    private init() {
        checkAllPermissions()
    }

    func checkAllPermissions() {
        hasAccessibilityPermission = AXIsProcessTrusted()
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
