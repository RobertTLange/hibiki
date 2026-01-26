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
    private var translatingObserver: AnyCancellable?
    private var collapsedObserver: AnyCancellable?
    private var keyboardMonitor: Any?
    private var lastHotkeyTime: Date?

    /// Cooldown period after a hotkey is triggered before Option-only can cancel
    /// This prevents the release of a hotkey combo (e.g., Option+L) from triggering stop
    /// 0.5s is enough time for key release while allowing quick intentional stops
    private let hotkeyStopCooldown: TimeInterval = 0.5

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

        // Check if CLI should be offered for installation
        checkCLIInstallation()

        // Observe playing state to show/hide audio player panel
        playingObserver = AppState.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                if isPlaying {
                    self?.showAudioPlayerPanel()
                } else if !AppState.shared.isSummarizing && !AppState.shared.isTranslating {
                    self?.hideAudioPlayerPanel()
                }
            }
        
        // Also observe summarizing state to show panel during LLM streaming
        summarizingObserver = AppState.shared.$isSummarizing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSummarizing in
                if isSummarizing {
                    self?.showAudioPlayerPanel()
                } else if !AppState.shared.isPlaying && !AppState.shared.isTranslating {
                    self?.hideAudioPlayerPanel()
                }
            }

        // Also observe translating state to show panel during translation
        translatingObserver = AppState.shared.$isTranslating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTranslating in
                if isTranslating {
                    self?.showAudioPlayerPanel()
                } else if !AppState.shared.isPlaying && !AppState.shared.isSummarizing {
                    self?.hideAudioPlayerPanel()
                }
            }

        // Observe collapsed state to resize panel
        collapsedObserver = AppState.shared.$isPanelCollapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelForCollapsedState()
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

    private func checkCLIInstallation() {
        let installer = CLIInstaller.shared

        // Only offer installation if running from /Applications and CLI not correctly linked
        guard installer.shouldOfferInstallation else {
            print("[Hibiki] CLI installation check: not needed (installed=\(installer.isInstalled), correctlyLinked=\(installer.isCorrectlyLinked), fromApps=\(installer.isRunningFromApplications))")
            return
        }

        print("[Hibiki] CLI installation should be offered")

        // Show dialog after a short delay to let the app finish launching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showCLIInstallDialog()
        }
    }

    private func showCLIInstallDialog() {
        // Temporarily become a regular app to show the dialog
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Install CLI Tool?"
        alert.informativeText = "Would you like to install the 'hibiki' command-line tool? This allows you to use Hibiki from the terminal.\n\nThe CLI will be installed to /usr/local/bin/hibiki"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()

        // Return to accessory mode
        NSApp.setActivationPolicy(.accessory)

        if response == .alertFirstButtonReturn {
            // Try to install
            CLIInstaller.shared.installWithAdminPrivileges { [weak self] result in
                switch result {
                case .success:
                    self?.showCLIInstallSuccessAlert()
                case .failure(let error):
                    if case .userCancelled = error {
                        // User cancelled, don't show error
                        return
                    }
                    self?.showCLIInstallErrorAlert(error: error)
                }
            }
        }
    }

    private func showCLIInstallSuccessAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "CLI Installed"
        alert.informativeText = "The 'hibiki' command is now available. You can use it from any terminal:\n\nhibiki --text \"Hello, world!\""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()

        NSApp.setActivationPolicy(.accessory)
    }

    private func showCLIInstallErrorAlert(error: CLIInstallError) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Installation Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()

        NSApp.setActivationPolicy(.accessory)
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
            if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hibiki TTS") {
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
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
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

        // Set default for translate+TTS (Option + L)
        if KeyboardShortcuts.getShortcut(for: .triggerTranslateTTS) == nil {
            KeyboardShortcuts.setShortcut(.init(.l, modifiers: [.option]), for: .triggerTranslateTTS)
        }

        // Set default for summarize+translate+TTS (Shift + Option + L)
        if KeyboardShortcuts.getShortcut(for: .triggerSummarizeTranslateTTS) == nil {
            KeyboardShortcuts.setShortcut(.init(.l, modifiers: [.shift, .option]), for: .triggerSummarizeTranslateTTS)
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
        guard let panel = audioPlayerPanel else { return }

        let position = PanelPosition(rawValue: AppState.shared.panelPosition) ?? .topRight
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        // Get the main screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        var x: CGFloat
        var y: CGFloat

        switch position {
        case .topRight:
            x = screenFrame.maxX - panelWidth - 20
            y = screenFrame.maxY - panelHeight - 20
        case .topLeft:
            x = screenFrame.minX + 20
            y = screenFrame.maxY - panelHeight - 20
        case .bottomRight:
            x = screenFrame.maxX - panelWidth - 20
            y = screenFrame.minY + 20
        case .bottomLeft:
            x = screenFrame.minX + 20
            y = screenFrame.minY + 20
        case .belowMenuBar:
            // Position below the status bar button
            if let button = statusItem.button,
               let buttonWindow = button.window {
                let buttonFrameInWindow = button.convert(button.bounds, to: nil)
                let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
                x = buttonFrameOnScreen.midX - panelWidth / 2
                y = buttonFrameOnScreen.minY - panelHeight - 4
            } else {
                // Fallback to top right if button not available
                x = screenFrame.maxX - panelWidth - 20
                y = screenFrame.maxY - panelHeight - 20
            }
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func updatePanelForCollapsedState() {
        guard let panel = audioPlayerPanel else { return }

        // Force the panel to recalculate its size based on the SwiftUI content
        if let hostingView = panel.contentView as? NSHostingView<AnyView> {
            hostingView.needsLayout = true
            hostingView.layoutSubtreeIfNeeded()
        }

        // Reposition the panel after size change
        positionPanelBelowMenuBar()
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard AppState.shared.isPlaying || AppState.shared.isSummarizing || AppState.shared.isTranslating else { return }

            // Check for Option key alone (stop) - triggered on flagsChanged
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // Option key pressed alone (no other modifiers)
                if flags == .option {
                    // Check cooldown period after hotkey trigger to prevent Option release from stopping
                    if let lastHotkey = AppState.shared.lastHotkeyTriggerTime,
                       let cooldown = self?.hotkeyStopCooldown,
                       Date().timeIntervalSince(lastHotkey) < cooldown {
                        // Within cooldown period - ignore Option-only stop
                        return
                    }
                    DispatchQueue.main.async {
                        AppState.shared.stopPlayback()
                    }
                }
            }
            // Check for Escape key (cancel)
            else if event.type == .keyDown && event.keyCode == 53 {
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

    // MARK: - URL Scheme Handling

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "hibiki" {
                CLIRequestHandler.shared.handle(url: url)
            }
        }
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
    static let triggerTranslateTTS = Self("triggerTranslateTTS")
    static let triggerSummarizeTranslateTTS = Self("triggerSummarizeTranslateTTS")
}
