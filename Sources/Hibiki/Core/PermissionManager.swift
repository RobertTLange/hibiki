import Cocoa
import ApplicationServices

/// Permission manager - NOT @Observable to avoid conflicts with SwiftUI observation.
/// Views should maintain their own @State for permission status and call checkAccessibility() to update.
final class PermissionManager {
    static let shared = PermissionManager()
    private var didAutoPromptThisLaunch = false

    private init() {}

    /// Check if accessibility permission is granted. Call this from main thread.
    func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibilityPermission(auto: Bool = false) {
        if auto {
            guard !didAutoPromptThisLaunch else { return }
            didAutoPromptThisLaunch = true
        }
        let prompt: () -> Void = { [weak self] in
            // This opens System Settings > Privacy > Accessibility with app highlighted
            let options: NSDictionary = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ]
            let trusted = AXIsProcessTrustedWithOptions(options)
            if !trusted {
                self?.bringAccessibilitySettingsToFront()
            }
        }

        if Thread.isMainThread {
            prompt()
        } else {
            DispatchQueue.main.async {
                prompt()
            }
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func bringAccessibilitySettingsToFront() {
        openAccessibilitySettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.activateSystemSettings()
        }
    }

    private func activateSystemSettings() {
        let bundleIds = ["com.apple.SystemSettings", "com.apple.systempreferences"]
        for bundleId in bundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate(options: [.activateAllWindows])
                break
            }
        }
    }
}
