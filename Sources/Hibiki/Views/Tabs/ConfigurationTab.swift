import SwiftUI
import KeyboardShortcuts

struct ConfigurationTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showKey = false
    @State private var hasAccessibility = false

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
