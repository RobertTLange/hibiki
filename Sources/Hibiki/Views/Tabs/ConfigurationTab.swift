import SwiftUI
import AppKit
import KeyboardShortcuts

struct ConfigurationTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showOpenAIKey = false
    @State private var showElevenLabsKey = false
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

    private var selectedTTSProvider: TTSProvider {
        TTSProvider(rawValue: appState.ttsProvider) ?? .openAI
    }

    private var retentionDaysBinding: Binding<Int> {
        Binding(
            get: {
                Swift.min(
                    Swift.max(appState.historyRetentionDays, HistoryManager.minRetentionDays),
                    HistoryManager.maxRetentionDays
                )
            },
            set: { newValue in
                let clamped = Swift.min(
                    Swift.max(newValue, HistoryManager.minRetentionDays),
                    HistoryManager.maxRetentionDays
                )
                appState.historyRetentionDays = clamped
                HistoryManager.shared.applyRetentionPolicy()
            }
        )
    }

    private var retentionMaxEntriesBinding: Binding<Int> {
        Binding(
            get: {
                Swift.min(
                    Swift.max(appState.historyRetentionMaxEntries, HistoryManager.minMaxEntries),
                    HistoryManager.maxMaxEntries
                )
            },
            set: { newValue in
                let clamped = Swift.min(
                    Swift.max(newValue, HistoryManager.minMaxEntries),
                    HistoryManager.maxMaxEntries
                )
                appState.historyRetentionMaxEntries = clamped
                HistoryManager.shared.applyRetentionPolicy()
            }
        )
    }

    private var retentionMaxDiskSpaceBinding: Binding<Double> {
        Binding(
            get: {
                Swift.min(
                    Swift.max(appState.historyRetentionMaxDiskSpaceMB, HistoryManager.minMaxDiskSpaceMB),
                    HistoryManager.maxMaxDiskSpaceMB
                )
            },
            set: { newValue in
                let clamped = Swift.min(
                    Swift.max(newValue, HistoryManager.minMaxDiskSpaceMB),
                    HistoryManager.maxMaxDiskSpaceMB
                )
                appState.historyRetentionMaxDiskSpaceMB = clamped
                HistoryManager.shared.applyRetentionPolicy()
            }
        )
    }

    private var historyDataDirectoryURL: URL {
        HistoryManager.shared.audioDirectory.deletingLastPathComponent()
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

                // Row 1: API Key + Permissions + CLI
                HStack(alignment: .top, spacing: 16) {
                    // API Key Section
                    GroupBox("API Keys") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("OpenAI (LLM + optional TTS)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack {
                                        if showOpenAIKey {
                                            TextField("sk-...", text: $appState.apiKey)
                                                .textFieldStyle(.roundedBorder)
                                        } else {
                                            SecureField("sk-...", text: $appState.apiKey)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                        Button(showOpenAIKey ? "Hide" : "Show") {
                                            showOpenAIKey.toggle()
                                        }
                                    }

                                    Link("Get an API key from OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                                Divider()
                                    .frame(maxHeight: .infinity)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ElevenLabs (TTS)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    HStack {
                                        if showElevenLabsKey {
                                            TextField("el-...", text: $appState.elevenLabsAPIKey)
                                                .textFieldStyle(.roundedBorder)
                                        } else {
                                            SecureField("el-...", text: $appState.elevenLabsAPIKey)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                        Button(showElevenLabsKey ? "Hide" : "Show") {
                                            showElevenLabsKey.toggle()
                                        }
                                    }

                                    Text("Voice ID (override default):")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("JBFqnCBsd6RMkjVDRZzb", text: $appState.elevenLabsVoiceID)
                                        .textFieldStyle(.roundedBorder)

                                    Link("Get an API key from ElevenLabs", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                                        .font(.caption)

                                    Link("Browse ElevenLabs voices", destination: URL(string: "https://elevenlabs.io/app/voice-library")!)
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }

                            Text("Env vars: OPENAI_API_KEY, ELEVENLABS_API_KEY")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: 16) {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Row 2: Voice + Playback Speed + Panel Position
                HStack(alignment: .top, spacing: 16) {
                    // Voice Section
                    GroupBox("Text to Speech") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Provider:", selection: $appState.ttsProvider) {
                                ForEach(TTSProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if selectedTTSProvider == .openAI {
                                Picker("Voice:", selection: $appState.selectedVoice) {
                                    ForEach(TTSVoice.allCases) { voice in
                                        Text(voice.rawValue.capitalized).tag(voice.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text("Choose the voice for OpenAI TTS.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(voiceDescription)
                                    .font(.caption)
                                    .foregroundColor(.primary.opacity(0.7))
                                    .italic()
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Model ID:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Picker("Model:", selection: $appState.elevenLabsModelID) {
                                        ForEach(ElevenLabsModel.allCases) { model in
                                            Text(model.displayName).tag(model.rawValue)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                Text("Voice ID is configurable in API Keys.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("OpenAI voices are ignored when provider is ElevenLabs.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Playback Section
                    GroupBox("Playback") {
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

                            Divider()

                            HStack {
                                Text("Volume:")

                                FlatSlider(
                                    value: Binding(
                                        get: { appState.playbackVolume },
                                        set: { appState.updatePlaybackVolume($0) }
                                    ),
                                    range: 0.0...AppState.maxPlaybackVolume,
                                    step: 0.01
                                )
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

                GroupBox("History Retention") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 16) {
                            HStack(spacing: 8) {
                                Text("Days")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer(minLength: 8)
                                Text("\(retentionDaysBinding.wrappedValue)")
                                    .font(.system(.body, design: .monospaced))
                                Stepper(
                                    "",
                                    value: retentionDaysBinding,
                                    in: HistoryManager.minRetentionDays...HistoryManager.maxRetentionDays
                                )
                                .labelsHidden()
                                .fixedSize()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Text("Max Entries")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer(minLength: 8)
                                Text("\(retentionMaxEntriesBinding.wrappedValue)")
                                    .font(.system(.body, design: .monospaced))
                                Stepper(
                                    "",
                                    value: retentionMaxEntriesBinding,
                                    in: HistoryManager.minMaxEntries...HistoryManager.maxMaxEntries,
                                    step: 100
                                )
                                .labelsHidden()
                                .fixedSize()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 8) {
                                Text("Max Audio MB")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer(minLength: 8)
                                Text("\(Int(retentionMaxDiskSpaceBinding.wrappedValue))")
                                    .font(.system(.body, design: .monospaced))
                                Stepper(
                                    "",
                                    value: retentionMaxDiskSpaceBinding,
                                    in: HistoryManager.minMaxDiskSpaceMB...HistoryManager.maxMaxDiskSpaceMB,
                                    step: 500
                                )
                                .labelsHidden()
                                .fixedSize()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("Default: 7 days, 50k entries, 10GB audio. Applies immediately.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Open Raw Data Directory") {
                            openHistoryDataDirectory()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }

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
                                appState.summarizationPrompt = AppState.defaultSummarizationPrompt
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
            PermissionManager.shared.requestAccessibilityPermission(auto: true)
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

    private func openHistoryDataDirectory() {
        let url = historyDataDirectoryURL
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        if !NSWorkspace.shared.open(url) {
            _ = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
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
