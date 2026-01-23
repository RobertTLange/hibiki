import SwiftUI
import KeyboardShortcuts

struct ConfigurationTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showKey = false
    @State private var hasAccessibility = false

    private let asciiArt = """
         _     _ _     _ _    _
        | |   (_) |   (_) |  (_)
        | |__  _| |__  _| | ___
        | '_ \\| | '_ \\| | |/ / |
        | | | | | |_) | |   <| |
        |_| |_|_|_.__/|_|_|\\_\\_|
        """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ASCII Art Header
                VStack(alignment: .trailing, spacing: 2) {
                    Text(asciiArt)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                    Text("Designed by RobertTLange")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

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

                // Playback Speed Section
                GroupBox("Playback Speed") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Default Speed:")
                            
                            Slider(
                                value: $appState.playbackSpeed,
                                in: 1.0...2.5,
                                step: 0.1
                            )
                            
                            Text(String(format: "%.1fx", appState.playbackSpeed))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 45, alignment: .trailing)
                        }
                        
                        HStack(spacing: 12) {
                            ForEach([1.0, 1.5, 2.0, 2.5], id: \.self) { speed in
                                Button(String(format: "%.1fx", speed)) {
                                    appState.playbackSpeed = speed
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(appState.playbackSpeed == speed ? .accentColor : nil)
                            }
                        }

                        Text("Speed can also be adjusted during playback.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Hotkey Section
                GroupBox("Hotkeys") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            KeyboardShortcuts.Recorder("Trigger TTS:", name: .triggerTTS)
                            Text("Select text in any app, then press this shortcut to read it aloud.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            KeyboardShortcuts.Recorder("Summarize + TTS:", name: .triggerSummarizeTTS)
                            Text("Summarize text with AI before reading aloud.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            KeyboardShortcuts.Recorder("Translate + TTS:", name: .triggerTranslateTTS)
                            Text("Translate text to target language before reading aloud.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            KeyboardShortcuts.Recorder("Summarize + Translate + TTS:", name: .triggerSummarizeTranslateTTS)
                            Text("Summarize, then translate text before reading aloud.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

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
                                .frame(height: 100)
                                .scrollContentBackground(.hidden)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }

                        HStack {
                            Button("Reset to Default") {
                                appState.summarizationPrompt = """
                                    Summarize the following text concisely while preserving the key information. \
                                    The summary should be suitable for text-to-speech, so write in complete sentences \
                                    and avoid bullet points or special formatting. Keep it under 3 paragraphs.
                                    """
                            }
                            .controlSize(.small)

                            Spacer()
                        }

                        Text("The summarization prompt controls how text is condensed before TTS.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Translation Section
                GroupBox("Translation") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Target Language:", selection: $appState.targetLanguage) {
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text("System Prompt:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextEditor(text: $appState.translationPrompt)
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

                        HStack {
                            Button("Reset to Default") {
                                appState.translationPrompt = """
                                    Translate the following text to {language}. Preserve the meaning, tone, and style. \
                                    Output only the translation without any explanations or notes.
                                    """
                            }
                            .controlSize(.small)

                            Spacer()

                            Text("Use {language} as placeholder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Select the language to translate text into before TTS. Set to \"None\" to disable translation.")
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
                            
                            if !hasAccessibility {
                                Button("Request Permission") {
                                    PermissionManager.shared.requestAccessibilityPermission()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        
                        // Use ternary instead of if/else block to avoid SwiftUI view diffing issues
                        Text(hasAccessibility 
                             ? "Hibiki can read selected text from other applications." 
                             : "Grant accessibility permission in System Settings > Privacy & Security > Accessibility.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
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
