import Cocoa
import SwiftUI
import KeyboardShortcuts
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var menu: NSMenu!
    private var doNotDisturbMenuItem: NSMenuItem?
    private var doNotDisturbSwitch: NSSwitch?
    private var recentTracksHeaderMenuItem: NSMenuItem?
    private var recentTrackMenuItems: [NSMenuItem] = []
    private var mainWindow: NSWindow?
    private var audioPlayerPanel: NSPanel?
    private var panelVisibilityObserver: AnyCancellable?
    private var collapsedObserver: AnyCancellable?
    private var menuPlaybackObserver: AnyCancellable?
    private var doNotDisturbObserver: AnyCancellable?
    private var historyEntriesObserver: AnyCancellable?
    private var manualPanelPinObserver: AnyCancellable?
    private var keyboardMonitor: Any?
    private var lastHotkeyTime: Date?
    private var pinnedPanelDisplayID: CGDirectDisplayID?
    private var usePinnedPanelScreen = false

    /// Cooldown period after a hotkey is triggered before Option-only can cancel
    /// This prevents the release of a hotkey combo (e.g., Option+L) from triggering stop
    /// 0.5s is enough time for key release while allowing quick intentional stops
    private let hotkeyStopCooldown: TimeInterval = 0.5
    private let recentTrackLimit = 5
    private lazy var recentTrackTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

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

        setupMenuObservers()
        setupPanelPinObserver()

        // Observe all activity flags together to show/hide audio player panel.
        // Include pending request queue depth to avoid hide/show gaps between queued items.
        panelVisibilityObserver = AppState.shared.$isPlaying
            .combineLatest(
                AppState.shared.$isSummarizing,
                AppState.shared.$isTranslating,
                AppState.shared.$isLoading
            )
            .combineLatest(AppState.shared.$pendingRequestCount)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, pendingRequests in
                let (isPlaying, isSummarizing, isTranslating, isLoading) = state
                if isPlaying || isSummarizing || isTranslating || isLoading || pendingRequests > 0 {
                    self?.showAudioPlayerPanel()
                } else {
                    self?.usePinnedPanelScreen = false
                    self?.pinnedPanelDisplayID = nil
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
        alert.informativeText = """
        The 'hibiki' command is now available. You can use it from any terminal:

        hibiki --text "Hello, world!"
        hibiki --file-name README.md
        """
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
        let dndMenuItem = NSMenuItem()
        dndMenuItem.view = makeDoNotDisturbMenuView()
        menu.addItem(dndMenuItem)
        doNotDisturbMenuItem = dndMenuItem

        menu.addItem(NSMenuItem.separator())
        let recentTracksHeaderItem = NSMenuItem(title: "Recent Tracks", action: nil, keyEquivalent: "")
        recentTracksHeaderItem.isEnabled = false
        menu.addItem(recentTracksHeaderItem)
        recentTracksHeaderMenuItem = recentTracksHeaderItem

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Hibiki", action: #selector(quitApp), keyEquivalent: "q"))

        refreshRecentTrackMenuItems()
        refreshDoNotDisturbMenuItem()

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

    @objc private func playRecentTrack(_ sender: NSMenuItem) {
        guard let entryIDString = sender.representedObject as? String,
              let entryID = UUID(uuidString: entryIDString),
              let entry = HistoryManager.shared.entries.first(where: { $0.id == entryID }) else {
            return
        }

        Task { @MainActor in
            AppState.shared.toggleHistoryPlayback(for: entry)
            self.refreshRecentTrackMenuItems()
        }
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

    private func setupMenuObservers() {
        menuPlaybackObserver = AppState.shared.$isPlaying
            .combineLatest(AppState.shared.$isPaused, AppState.shared.$activeHistoryReplayEntryId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.refreshRecentTrackMenuItems()
            }

        doNotDisturbObserver = AppState.shared.$isDoNotDisturbEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDoNotDisturbMenuItem()
            }

        historyEntriesObserver = HistoryManager.shared.entriesDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshRecentTrackMenuItems()
            }
    }

    @objc private func handleDoNotDisturbSwitchChanged(_ sender: NSSwitch) {
        let isEnabled = sender.state == .on
        Task { @MainActor in
            AppState.shared.setDoNotDisturbEnabled(isEnabled)
        }
    }

    private func makeDoNotDisturbMenuView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 24))

        let label = NSTextField(labelWithString: "Do Not Disturb")
        label.frame = NSRect(x: 16, y: 4, width: 160, height: 16)
        label.textColor = .labelColor
        container.addSubview(label)

        let toggle = NSSwitch(frame: NSRect(x: 196, y: 0, width: 50, height: 24))
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = #selector(handleDoNotDisturbSwitchChanged(_:))
        container.addSubview(toggle)

        doNotDisturbSwitch = toggle
        return container
    }

    private func refreshDoNotDisturbMenuItem() {
        guard let doNotDisturbMenuItem, let doNotDisturbSwitch else { return }
        let enabled = AppState.shared.isDoNotDisturbEnabled
        doNotDisturbMenuItem.state = .off
        doNotDisturbSwitch.state = enabled ? .on : .off
    }

    private func refreshRecentTrackMenuItems() {
        guard let menu = menu, let header = recentTracksHeaderMenuItem else { return }

        for item in recentTrackMenuItems {
            menu.removeItem(item)
        }
        recentTrackMenuItems.removeAll()

        let headerIndex = menu.index(of: header)
        guard headerIndex >= 0 else { return }

        let entries = Array(HistoryManager.shared.entries.prefix(recentTrackLimit))
        var insertionIndex = headerIndex + 1

        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No tracks yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.insertItem(emptyItem, at: insertionIndex)
            recentTrackMenuItems = [emptyItem]
            return
        }

        for entry in entries {
            let item = NSMenuItem(
                title: recentTrackTitle(for: entry),
                action: #selector(playRecentTrack(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = entry.id.uuidString
            item.image = recentTrackIcon(for: entry)
            menu.insertItem(item, at: insertionIndex)
            recentTrackMenuItems.append(item)
            insertionIndex += 1
        }
    }

    private func recentTrackTitle(for entry: HistoryEntry) -> String {
        let timestamp = recentTrackTimeFormatter.string(from: entry.timestamp)
        let flattened = entry.displayText.replacingOccurrences(of: "\n", with: " ")
        let preview = flattened.count > 46 ? String(flattened.prefix(46)) + "..." : flattened
        return "\(timestamp)  \(preview)"
    }

    private func recentTrackIcon(for entry: HistoryEntry) -> NSImage? {
        let appState = AppState.shared
        let isActive = appState.activeHistoryReplayEntryId == entry.id
        let symbolName = isActive && appState.isPlaying && !appState.isPaused ? "pause.fill" : "play.fill"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
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

    private func setupPanelPinObserver() {
        manualPanelPinObserver = NotificationCenter.default.publisher(for: .hibikiPinPanelToManualSelection)
            .sink { [weak self] _ in
                self?.pinPanelToActiveScreenForManualSelection()
            }
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

        // Use pinned screen for explicit request sources (manual selection/CLI).
        guard let screen = preferredPanelScreen() else { return }
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
            // For source-pinned placement, anchor near top-center of pinned display.
            // Otherwise position relative to status bar item.
            if usePinnedPanelScreen {
                x = screenFrame.midX - panelWidth / 2
                y = screenFrame.maxY - panelHeight - 8
            } else if let button = statusItem.button,
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
            guard AppState.shared.isPlaying
                || AppState.shared.isSummarizing
                || AppState.shared.isTranslating
                || AppState.shared.isLoading
                || AppState.shared.pendingRequestCount > 0 else { return }

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
                    Task { @MainActor in
                        AppState.shared.stopPlayback()
                    }
                }
            }
            // Check for Escape key (cancel)
            else if event.type == .keyDown && event.keyCode == 53 {
                Task { @MainActor in
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
                pinPanelToScreenForCLIRequest(url: url)
                CLIRequestHandler.shared.handle(url: url)
            }
        }
    }

    private func pinPanelToScreenForCLIRequest(url: URL) {
        if let requestedDisplayID = requestedDisplayID(from: url),
           let requestedScreen = NSScreen.screens.first(where: { displayID(for: $0) == requestedDisplayID }) {
            pinnedPanelDisplayID = requestedDisplayID
            usePinnedPanelScreen = true
            DebugLogger.shared.info(
                "Panel pinned from CLI request to display \(requestedDisplayID) (\(requestedScreen.localizedName))",
                source: "AppDelegate"
            )
            return
        }

        pinPanelToActiveScreenForCLIRequest()
    }

    private func pinPanelToActiveScreenForCLIRequest() {
        guard let screen = currentActiveScreen(),
              let displayID = displayID(for: screen) else {
            DebugLogger.shared.warning("Panel pin failed: no active screen", source: "AppDelegate")
            return
        }

        pinnedPanelDisplayID = displayID
        usePinnedPanelScreen = true
        DebugLogger.shared.info(
            "Panel pinned to display \(displayID) (\(screen.localizedName))",
            source: "AppDelegate"
        )
    }

    private func pinPanelToActiveScreenForManualSelection() {
        guard let screen = currentActiveScreen(),
              let displayID = displayID(for: screen) else {
            DebugLogger.shared.warning("Manual panel pin failed: no active screen", source: "AppDelegate")
            return
        }

        pinnedPanelDisplayID = displayID
        usePinnedPanelScreen = true
        DebugLogger.shared.debug(
            "Manual panel pin to display \(displayID) (\(screen.localizedName))",
            source: "AppDelegate"
        )
    }

    private func preferredPanelScreen() -> NSScreen? {
        if usePinnedPanelScreen,
           let pinnedPanelDisplayID,
           let pinned = NSScreen.screens.first(where: { displayID(for: $0) == pinnedPanelDisplayID }) {
            return pinned
        }
        return currentActiveScreen() ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func requestedDisplayID(from url: URL) -> CGDirectDisplayID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let displayString = components.queryItems?.first(where: { $0.name == "display" })?.value,
              let displayID = UInt32(displayString) else {
            return nil
        }
        return CGDirectDisplayID(displayID)
    }

    private func currentActiveScreen() -> NSScreen? {
        if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           let focusedDisplayID = focusedWindowDisplayID(for: frontmostPID),
           let focusedScreen = NSScreen.screens.first(where: { displayID(for: $0) == focusedDisplayID }) {
            DebugLogger.shared.debug("Using focused-window display \(focusedDisplayID)", source: "AppDelegate")
            return focusedScreen
        }

        if let activeDisplayID = frontmostWindowDisplayID(),
           let frontmostWindowScreen = NSScreen.screens.first(where: { displayID(for: $0) == activeDisplayID }) {
            return frontmostWindowScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }
        return NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func focusedWindowDisplayID(for pid: pid_t) -> CGDirectDisplayID? {
        guard let bounds = focusedWindowBounds(for: pid) else {
            return nil
        }
        return displayIDForWindowBounds(bounds)
    }

    private func focusedWindowBounds(for pid: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(pid)

        var windowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        guard focusedWindowResult == .success,
              let windowElement = windowValue else {
            return nil
        }

        let windowAXElement = windowElement as! AXUIElement

        var positionValue: CFTypeRef?
        let positionResult = AXUIElementCopyAttributeValue(
            windowAXElement,
            kAXPositionAttribute as CFString,
            &positionValue
        )

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(
            windowAXElement,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue else {
            return nil
        }
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetType(positionAXValue) == .cgPoint,
              AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetType(sizeAXValue) == .cgSize,
              AXValueGetValue(sizeAXValue, .cgSize, &size),
              size.width > 1,
              size.height > 1 else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func displayIDForWindowBounds(_ windowBounds: CGRect) -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return nil
        }

        var bestDisplayID: CGDirectDisplayID?
        var bestArea: CGFloat = 0

        for display in displays {
            let displayBounds = CGDisplayBounds(display)
            let overlapArea = intersectionArea(windowBounds, displayBounds)
            if overlapArea > bestArea {
                bestArea = overlapArea
                bestDisplayID = display
            }
        }

        if let bestDisplayID {
            return bestDisplayID
        }

        let center = CGPoint(x: windowBounds.midX, y: windowBounds.midY)
        return displayIDAtGlobalPoint(center)
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        guard !overlap.isNull && !overlap.isEmpty else { return 0 }
        return overlap.width * overlap.height
    }

    private func frontmostWindowDisplayID() -> CGDirectDisplayID? {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else {
            return nil
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if let displayID = firstDisplayID(in: windowInfos, matchingPID: frontmostPID) {
            return displayID
        }

        return firstDisplayID(in: windowInfos, matchingPID: nil)
    }

    private func firstDisplayID(in windowInfos: [[String: Any]], matchingPID: pid_t?) -> CGDirectDisplayID? {
        for info in windowInfos {
            if let matchingPID, let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID != matchingPID {
                continue
            }

            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }

            if let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool, !isOnscreen {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 1,
                  bounds.height > 1 else {
                continue
            }

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if let displayID = displayIDAtGlobalPoint(center) {
                return displayID
            }
        }

        return nil
    }

    private func displayIDAtGlobalPoint(_ point: CGPoint) -> CGDirectDisplayID? {
        var displayID = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        let result = withUnsafeMutablePointer(to: &displayID) { displayPtr in
            CGGetDisplaysWithPoint(point, 1, displayPtr, &displayCount)
        }
        guard result == .success, displayCount > 0 else {
            return nil
        }
        return displayID
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(truncating: number)
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
