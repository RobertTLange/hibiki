import SwiftUI
import KeyboardShortcuts

struct ConfigurationTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showKey = false
    @State private var hasAccessibility = false
    @State private var cliInstallStatus: CLIInstallStatus = .unknown
    @State private var isInstallingCLI = false

    private let asciiArt = """
         _     _ _     _ _    _              .-----------.
        | |   (_) |   (_) |  (_)          .-'   .-----.   '-.
        | |__  _| |__  _| | ___          /   .--'     '--.   \\
        | '_ \\| | '_ \\| | |/ / |        /   /   .-----.   \\   \\
        | | | | | |_) | |   <| |       /   /   /       \\   \\   \\
        |_| |_|_|_.__/|_|_|\\_\\_|      |   |   |   (O)   |   |   |
        """

    /// Binding for the current language's translation prompt
    private var translationPromptBinding: Binding<String> {
        Binding(
            get: { appState.currentTranslationPrompt },
            set: { appState.currentTranslationPrompt = $0 }
        )
    }

    /// Description for the currently selected voice
    private var voiceDescription: String {
        switch appState.selectedVoice {
        case "alloy": return "Balanced, versatile, and neutral."
        case "ash": return "Warm, friendly, and engaging."
        case "ballad": return "Expressive and gentle."
        case "coral": return "Clear and pleasant."
        case "echo": return "Authoritative and deep."
        case "fable": return "Storyteller-like, with a distinct British or dramatic accent."
        case "nova": return "Bright, energetic, and youthful."
        case "onyx": return "Smooth, dark, and confident."
        case "sage": return "Wise, soft, and calm."
        case "shimmer": return "Melodic, light, and engaging."
        case "verse": return "Articulate and professional."
        default: return ""
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ASCII Art Header
                VStack(alignment: .trailing, spacing: 2) {
                    Text(asciiArt)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    Link("@RobertTLange", destination: URL(string: "https://twitter.com/RobertTLange")!)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                // Row 1: API Key + Permissions
                HStack(alignment: .top, spacing: 16) {
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

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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

                                if !hasAccessibility {
                                    Button("Request") {
                                        PermissionManager.shared.requestAccessibilityPermission()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }

                            Text(hasAccessibility
                                 ? "Hibiki can read selected text."
                                 : "Grant in System Settings > Privacy > Accessibility.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // CLI Tool Section
                    GroupBox("CLI Tool") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: cliInstallStatus.iconName)
                                    .foregroundColor(cliInstallStatus.iconColor)
                                    .font(.title2)

                                VStack(alignment: .leading) {
                                    Text("Terminal Command")
                                        .fontWeight(.medium)
                                    Text(cliInstallStatus.statusText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if isInstallingCLI {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else if cliInstallStatus == .notInstalled {
                                    Button(cliInstallStatus.buttonTitle) {
                                        installCLI()
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else {
                                    Button(cliInstallStatus.buttonTitle) {
                                        installCLI()
                                    }
                                    .disabled(!cliInstallStatus.canInstall)
                                }
                            }

                            Text(cliInstallStatus.helpText)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Row 2: Voice + Playback Speed + Panel Position
                HStack(alignment: .top, spacing: 16) {
                    // Voice Section
                    GroupBox("Voice") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Voice:", selection: $appState.selectedVoice) {
                                ForEach(TTSVoice.allCases) { voice in
                                    Text(voice.rawValue.capitalized).tag(voice.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Choose the voice for text-to-speech.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(voiceDescription)
                                .font(.caption)
                                .foregroundColor(.primary.opacity(0.7))
                                .italic()

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Playback Speed Section
                    GroupBox("Playback Speed") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Speed:")

                                Slider(
                                    value: $appState.playbackSpeed,
                                    in: 1.0...2.5,
                                    step: 0.1
                                )

                                Text(String(format: "%.1fx", appState.playbackSpeed))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 45, alignment: .trailing)
                            }

                            HStack(spacing: 8) {
                                ForEach([1.0, 1.5, 2.0, 2.5], id: \.self) { speed in
                                    Button(String(format: "%.1fx", speed)) {
                                        appState.playbackSpeed = speed
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(appState.playbackSpeed == speed ? .accentColor : nil)
                                }
                            }

                            Text("Adjustable during playback.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Panel Position Section
                    GroupBox("Panel Position") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Position:", selection: $appState.panelPosition) {
                                ForEach(PanelPosition.allCases) { position in
                                    Text(position.displayName).tag(position.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Initial position of the audio player panel.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("Use the collapse button (▲) to minimize.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Hotkey Section (2 columns)
                GroupBox("Hotkeys") {
                    HStack(alignment: .top, spacing: 24) {
                        // Left Column: Trigger TTS, Summarize + TTS
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                KeyboardShortcuts.Recorder("Trigger TTS:", name: .triggerTTS)
                                Text("Read selected text aloud.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                KeyboardShortcuts.Recorder("Summarize + TTS:", name: .triggerSummarizeTTS)
                                Text("Summarize then read aloud.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Right Column: Translate + TTS, Summarize + Translate + TTS
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                KeyboardShortcuts.Recorder("Translate + TTS:", name: .triggerTranslateTTS)
                                Text("Translate then read aloud.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                KeyboardShortcuts.Recorder("Sum. + Trans. + TTS:", name: .triggerSummarizeTranslateTTS)
                                Text("Summarize, translate, then read.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }

                // Row 4: Summarization + Translation
                HStack(alignment: .top, spacing: 16) {
                    // Summarization Section
                    GroupBox("Summarization") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Model:", selection: $appState.summarizationModel) {
                                ForEach(LLMModel.allCases) { model in
                                    Text(model.displayName).tag(model.rawValue)
                                }
                            }
                            .pickerStyle(.menu)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("System Prompt:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextEditor(text: $appState.summarizationPrompt)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 80)
                                    .scrollContentBackground(.hidden)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }

                            Button("Reset to Default") {
                                appState.summarizationPrompt = """
                                    Summarize the following text concisely while preserving the key information. \
                                    The summary should be suitable for text-to-speech, so write in complete sentences \
                                    and avoid bullet points or special formatting. Keep it under 3 paragraphs.
                                    """
                            }
                            .controlSize(.small)

                            Text("Controls how text is condensed before TTS.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity)

                    // Translation Section
                    GroupBox("Translation") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                Picker("Language:", selection: $appState.targetLanguage) {
                                    ForEach(TargetLanguage.allCases) { language in
                                        Text(language.displayName).tag(language.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)

                                Picker("Model:", selection: $appState.translationModelSetting) {
                                    ForEach(LLMModel.allCases) { model in
                                        Text(model.displayName).tag(model.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            if let language = TargetLanguage(rawValue: appState.targetLanguage), language != .none {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("System Prompt:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    TextEditor(text: translationPromptBinding)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(height: 80)
                                        .scrollContentBackground(.hidden)
                                        .background(Color(NSColor.textBackgroundColor))
                                        .cornerRadius(4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                        )
                                }

                                Button("Reset to Default") {
                                    appState.currentTranslationPrompt = language.defaultPrompt
                                }
                                .controlSize(.small)
                            }

                            Text("Set to \"None\" to disable translation.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            checkPermissions(autoOpen: true)
            checkCLIStatus()
        }
    }

    private func checkPermissions(autoOpen: Bool = false) {
        hasAccessibility = PermissionManager.shared.checkAccessibility()

        // Automatically open Accessibility settings if permission not granted
        if autoOpen && !hasAccessibility {
            PermissionManager.shared.requestAccessibilityPermission()
        }
    }

    private func checkCLIStatus() {
        let installer = CLIInstaller.shared
        if !installer.isRunningFromApplications {
            cliInstallStatus = .notFromApplications
        } else if installer.isCorrectlyLinked {
            cliInstallStatus = .installed
        } else if installer.isInstalled {
            cliInstallStatus = .outdated
        } else {
            cliInstallStatus = .notInstalled
        }
    }

    private func installCLI() {
        isInstallingCLI = true
        CLIInstaller.shared.installWithAdminPrivileges { result in
            isInstallingCLI = false
            switch result {
            case .success:
                cliInstallStatus = .installed
            case .failure(let error):
                if case .userCancelled = error {
                    // User cancelled, just refresh status
                    checkCLIStatus()
                } else {
                    // Show error (status unchanged)
                    checkCLIStatus()
                }
            }
        }
    }
}

/// Status of CLI tool installation
enum CLIInstallStatus {
    case unknown
    case notFromApplications
    case notInstalled
    case outdated
    case installed

    var iconName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .notFromApplications: return "info.circle"
        case .notInstalled: return "xmark.circle.fill"
        case .outdated: return "exclamationmark.triangle.fill"
        case .installed: return "checkmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .unknown: return .secondary
        case .notFromApplications: return .secondary
        case .notInstalled: return .red
        case .outdated: return .orange
        case .installed: return .green
        }
    }

    var statusText: String {
        switch self {
        case .unknown: return "Checking..."
        case .notFromApplications: return "Run from Applications"
        case .notInstalled: return "Not installed"
        case .outdated: return "Needs update"
        case .installed: return "Installed"
        }
    }

    var buttonTitle: String {
        switch self {
        case .unknown, .notFromApplications: return "Refresh"
        case .notInstalled: return "Install"
        case .outdated: return "Update"
        case .installed: return "Reinstall"
        }
    }

    var helpText: String {
        switch self {
        case .unknown:
            return "Checking CLI installation status..."
        case .notFromApplications:
            return "Move Hibiki to /Applications to install CLI."
        case .notInstalled:
            return "Install to use 'hibiki' from terminal."
        case .outdated:
            return "Update to link CLI to current app."
        case .installed:
            return "Run: hibiki --text \"Hello!\""
        }
    }

    var canInstall: Bool {
        switch self {
        case .notInstalled, .outdated, .installed: return true
        case .unknown, .notFromApplications: return false
        }
    }
}
