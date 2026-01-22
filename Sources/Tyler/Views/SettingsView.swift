import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showKey = false
    @State private var hasAccessibility = false
    @State private var logger = DebugLogger.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // API Key Section
                GroupBox("OpenAI API Key") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if showKey {
                                TextField("sk-...", text: $appState.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-...", text: $appState.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(showKey ? "Hide" : "Show") {
                                showKey.toggle()
                            }
                        }

                        Link("Get an API key from OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

                // Voice Section
                GroupBox("Voice") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Voice:", selection: $appState.selectedVoice) {
                            ForEach(TTSVoice.allCases) { voice in
                                Text(voice.rawValue.capitalized).tag(voice.rawValue)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Choose the voice for text-to-speech.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Hotkey Section
                GroupBox("Hotkey") {
                    VStack(alignment: .leading, spacing: 8) {
                        KeyboardShortcuts.Recorder("Trigger TTS:", name: .triggerTTS)

                        Text("Select text in any app, then press this shortcut to read it aloud.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Permissions Section
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(hasAccessibility ? .green : .red)
                                .font(.title2)

                            VStack(alignment: .leading) {
                                Text("Accessibility")
                                    .fontWeight(.medium)
                                Text(hasAccessibility ? "Permission granted" : "Permission required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Refresh") {
                                checkPermissions()
                            }
                        }

                        Divider()

                        if !hasAccessibility {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("To grant permission:")
                                    .font(.caption)
                                    .fontWeight(.medium)

                                Text("1. Click 'Open System Settings' below\n2. Click the + button\n3. Click 'Reveal in Finder' below, then drag Tyler to the list\n4. Make sure Tyler's toggle is ON\n5. Click 'Restart Tyler'")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                // Show the executable path
                                if let execPath = Bundle.main.executablePath {
                                    Text("Executable: \(execPath)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }

                            HStack {
                                Button("Open System Settings") {
                                    PermissionManager.shared.openAccessibilitySettings()
                                }

                                Button("Reveal in Finder") {
                                    revealInFinder()
                                }

                                Button("Restart Tyler") {
                                    restartApp()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Text("Tyler can read selected text from other applications.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Debug Logs Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Debug Logs")
                                .fontWeight(.medium)

                            Text("(\(logger.entries.count) entries)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button("Clear") {
                                logger.clear()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if logger.entries.isEmpty {
                            Text("No log entries yet. Trigger some actions to see logs.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            DebugLogTableView(entries: logger.entries)
                                .frame(minHeight: 200, maxHeight: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 650)
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        // AXIsProcessTrusted() is the authoritative check
        hasAccessibility = AXIsProcessTrusted()
        PermissionManager.shared.checkAllPermissions()
        print("[Tyler] AXIsProcessTrusted: \(hasAccessibility)")
    }

    private func revealInFinder() {
        // Reveal the app bundle (or executable if not in a bundle) in Finder
        let pathToReveal: String
        if let bundlePath = Bundle.main.bundlePath as String?,
           bundlePath.hasSuffix(".app") {
            pathToReveal = bundlePath
        } else if let execPath = Bundle.main.executablePath {
            pathToReveal = execPath
        } else {
            return
        }

        NSWorkspace.shared.selectFile(pathToReveal, inFileViewerRootedAtPath: "")
    }

    private func restartApp() {
        let task = Process()
        task.launchPath = "/bin/sh"

        // Check if we're running as an .app bundle or bare executable
        if let bundlePath = Bundle.main.bundlePath as String?,
           bundlePath.hasSuffix(".app") {
            // Running as .app bundle - use open command
            task.arguments = ["-c", "sleep 0.5 && open \"\(bundlePath)\""]
        } else if let execPath = Bundle.main.executablePath {
            // Running as bare executable (e.g., swift run) - execute directly
            task.arguments = ["-c", "sleep 0.5 && \"\(execPath)\""]
        } else {
            print("[Tyler] Could not determine path to restart")
            return
        }

        print("[Tyler] Restarting with: \(task.arguments ?? [])")
        task.launch()
        NSApp.terminate(nil)
    }
}
