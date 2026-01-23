import Cocoa
import SwiftUI
import KeyboardShortcuts
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menu: NSMenu!
    private var mainWindow: NSWindow?
    private var audioPlayerPanel: NSPanel?
    private var playingObserver: AnyCancellable?
    private var summarizingObserver: AnyCancellable?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure only one instance is running
        if !ensureSingleInstance() {
            NSApp.terminate(nil)
            return
        }

        // Set the app icon
        setupAppIcon()

        // Hide dock icon - agent app behavior
        NSApp.setActivationPolicy(.accessory)

        // Create the status bar item
        setupStatusItem()

        // Register default hotkey shortcut
        setupDefaultHotkey()

        // Check permissions on launch (just log the result, don't need to store it)
        let hasAccess = PermissionManager.shared.checkAccessibility()
        print("[Hibiki] Accessibility permission on launch: \(hasAccess)")

        // Observe playing state to show/hide audio player panel
        playingObserver = AppState.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                if isPlaying {
                    self?.showAudioPlayerPanel()
                } else if !AppState.shared.isSummarizing {
                    self?.hideAudioPlayerPanel()
                }
            }
        
        // Also observe summarizing state to show panel during LLM streaming
        summarizingObserver = AppState.shared.$isSummarizing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSummarizing in
                if isSummarizing {
                    self?.showAudioPlayerPanel()
                } else if !AppState.shared.isPlaying {
                    self?.hideAudioPlayerPanel()
                }
            }
        
        // Auto-open settings window on launch (useful for development)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.openSettings()
        }
    }

    private func setupAppIcon() {
        if let iconURL = Bundle.main.url(forResource: "hibiki", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
    }

    /// Returns true if this is the only instance, false if another instance is already running
    private func ensureSingleInstance() -> Bool {
        let dominated = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        let otherInstances = dominated.filter { $0 != NSRunningApplication.current }

        if !otherInstances.isEmpty {
            // Another instance is already running - activate it and quit this one
            otherInstances.first?.activate()
            return false
        }
        return true
    }

    private func setupStatusItem() {
        // Create status item with fixed length to ensure visibility
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Create menu
        menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hibiki TTS", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Ready - Press ⌥F to speak", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Hibiki", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu

        if let button = statusItem.button {
            // Use text as fallback
            button.title = "T"

            // Try SF Symbol
            if let image = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "Hibiki TTS") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.title = ""
            }
        }

        // Create popover for future use
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(AppState.shared)
        )
    }

    @objc private func openSettings() {
        // Temporarily become a regular app to accept keyboard input
        NSApp.setActivationPolicy(.regular)

        if mainWindow == nil {
            let mainView = MainSettingsView()
                .environmentObject(AppState.shared)

            mainWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 750, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            mainWindow?.title = "Hibiki"
            mainWindow?.contentView = NSHostingView(rootView: mainView)
            mainWindow?.center()
            mainWindow?.isReleasedWhenClosed = false
            mainWindow?.delegate = self
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func setupDefaultHotkey() {
        // Set default if not already configured (Option + F)
        if KeyboardShortcuts.getShortcut(for: .triggerTTS) == nil {
            KeyboardShortcuts.setShortcut(.init(.f, modifiers: [.option]), for: .triggerTTS)
        }

        // Set default for summarize+TTS (Shift + Option + F)
        if KeyboardShortcuts.getShortcut(for: .triggerSummarizeTTS) == nil {
            KeyboardShortcuts.setShortcut(.init(.f, modifiers: [.shift, .option]), for: .triggerSummarizeTTS)
        }
    }

    // MARK: - Audio Player Panel

    private func showAudioPlayerPanel() {
        if audioPlayerPanel == nil {
            createAudioPlayerPanel()
        }

        // Position panel below the status bar item
        positionPanelBelowMenuBar()
        audioPlayerPanel?.orderFront(nil)

        // Install global keyboard monitor for S and Esc
        installKeyboardMonitor()
    }

    private func hideAudioPlayerPanel() {
        audioPlayerPanel?.orderOut(nil)
        removeKeyboardMonitor()
    }

    private func createAudioPlayerPanel() {
        // Taller to accommodate streaming summary text
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let contentView = AudioPlayerPanel(audioLevelMonitor: AppState.shared.audioLevelMonitor)
            .environmentObject(AppState.shared)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        audioPlayerPanel = panel
    }

    private func positionPanelBelowMenuBar() {
        guard let panel = audioPlayerPanel,
              let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Get the button's frame in screen coordinates
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)

        // Position panel below the button, centered
        let panelWidth = panel.frame.width
        let x = buttonFrameOnScreen.midX - panelWidth / 2
        let y = buttonFrameOnScreen.minY - panel.frame.height - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard AppState.shared.isPlaying || AppState.shared.isSummarizing else { return }

            // Check for 'S' key (stop)
            if event.keyCode == 1 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                DispatchQueue.main.async {
                    AppState.shared.stopPlayback()
                }
            }
            // Check for Escape key (cancel)
            else if event.keyCode == 53 {
                DispatchQueue.main.async {
                    AppState.shared.stopPlayback()
                }
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        StreamingAudioPlayer.shared.stop()
        removeKeyboardMonitor()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Return to accessory mode when main window closes
        if let closingWindow = notification.object as? NSWindow,
           closingWindow == mainWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// Define keyboard shortcut names
extension KeyboardShortcuts.Name {
    static let triggerTTS = Self("triggerTTS")
    static let triggerSummarizeTTS = Self("triggerSummarizeTTS")
}
