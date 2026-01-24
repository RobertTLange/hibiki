import SwiftUI
import KeyboardShortcuts

struct ConfigurationTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showKey = false
    @State private var hasAccessibility = false

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
                }
                .fixedSize(horizontal: false, vertical: true)

                // Row 2: Voice + Playback Speed
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
            checkPermissions()
        }
    }

    private func checkPermissions() {
        hasAccessibility = PermissionManager.shared.checkAccessibility()
    }
}
