import Cocoa
import ApplicationServices
import Carbon.HIToolbox

final class AccessibilityManager {
    static let shared = AccessibilityManager()
    private let logger = DebugLogger.shared

    private init() {}

    /// Gets the currently selected text from the frontmost application
    func getSelectedText() throws -> String? {
        logger.debug("getSelectedText() called", source: "Accessibility")

        let isTrusted = AXIsProcessTrusted()
        logger.debug("AXIsProcessTrusted: \(isTrusted)", source: "Accessibility")

        guard isTrusted else {
            logger.error("Accessibility permission denied", source: "Accessibility")
            throw AccessibilityError.permissionDenied
        }

        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            logger.error("No frontmost application", source: "Accessibility")
            throw AccessibilityError.noFocusedElement
        }
        logger.debug("Frontmost app: \(frontApp.localizedName ?? "unknown") (pid: \(frontApp.processIdentifier))", source: "Accessibility")

        // First try the accessibility API
        if let text = tryAccessibilityAPI(for: frontApp) {
            return text
        }

        // Fallback to clipboard method for apps like Chrome that don't report selected text properly
        logger.info("Trying clipboard fallback method", source: "Accessibility")
        return tryClipboardMethod()
    }

    private func tryAccessibilityAPI(for frontApp: NSRunningApplication) -> String? {
        // Create element for the frontmost app
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Get the focused element from the app
        var focusedElement: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        logger.debug("Focus result: \(focusResult.rawValue) (success=0)", source: "Accessibility")

        guard focusResult == .success,
              let element = focusedElement else {
            logger.debug("No focused element found, result: \(focusResult.rawValue)", source: "Accessibility")
            return nil
        }

        // Get the role of the focused element for debugging
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            logger.debug("Focused element role: \(role)", source: "Accessibility")
        }

        // Get the selected text from the focused element
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        logger.debug("Selected text result: \(textResult.rawValue) (success=0)", source: "Accessibility")

        if textResult == .success {
            if let text = selectedText as? String {
                logger.debug("Raw selected text length: \(text.count), isEmpty: \(text.isEmpty)", source: "Accessibility")
                logger.debug("Raw text bytes: \(Array(text.utf8.prefix(20)))", source: "Accessibility")

                // Check for NBSP or whitespace-only (Chrome returns NBSP for selected text)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Also check for non-breaking space (U+00A0)
                let nbspTrimmed = trimmed.replacingOccurrences(of: "\u{00A0}", with: "")
                if nbspTrimmed.isEmpty {
                    logger.warning("Selected text is only whitespace/NBSP, will try clipboard", source: "Accessibility")
                    return nil
                }

                logger.info("Got selected text via accessibility: \(text.count) chars", source: "Accessibility")
                return text
            }
        }

        return nil
    }

    private func tryClipboardMethod() -> String? {
        let pasteboard = NSPasteboard.general

        // Keep the user's clipboard, whatever it holds, to put back afterwards. The clipboard
        // is not cleared up front: the change count tells us whether the copy happened, and
        // if it did not, there is nothing to restore.
        let snapshot = PasteboardSnapshot(of: pasteboard)
        let changeCountBeforeCopy = pasteboard.changeCount

        logger.debug("Simulating Cmd+C", source: "Accessibility")
        simulateCopy()

        // Wait for the frontmost app to service the copy.
        let deadline = Date().addingTimeInterval(0.25)
        while pasteboard.changeCount == changeCountBeforeCopy, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        guard pasteboard.changeCount != changeCountBeforeCopy else {
            logger.warning("Clipboard method failed: nothing was copied", source: "Accessibility")
            return nil
        }

        let copiedText = pasteboard.string(forType: .string)
        let changeCountAfterCopy = pasteboard.changeCount

        // Put the original clipboard back shortly after, unless something else has been
        // copied in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard pasteboard.changeCount == changeCountAfterCopy else { return }
            snapshot.restore(to: pasteboard)
        }

        guard let text = copiedText,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("Clipboard method failed: copy produced no text", source: "Accessibility")
            return nil
        }

        logger.info("Got selected text via clipboard: \(text.count) chars", source: "Accessibility")
        return text
    }

    private func simulateCopy() {
        // Create Cmd+C key event
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down for Cmd+C
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        cDown?.flags = .maskCommand

        // Key up
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)

        // Post events
        cmdDown?.post(tap: .cghidEventTap)
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}

enum AccessibilityError: Error, LocalizedError {
    case permissionDenied
    case noFocusedElement
    case noSelectedText

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Accessibility permission not granted"
        case .noFocusedElement:
            return "No focused element found"
        case .noSelectedText:
            return "No text is selected"
        }
    }
}
