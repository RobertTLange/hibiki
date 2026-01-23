import SwiftUI

struct AudioPlayerPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioLevelMonitor: AudioLevelMonitor

    var body: some View {
        VStack(spacing: 8) {
            // Waveform visualization (always shown)
            WaveformView(level: audioLevelMonitor.currentLevel, barCount: 50)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            // Streaming summary text below waveform (during summarization)
            if appState.isSummarizing || !appState.streamingSummary.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(appState.streamingSummary.isEmpty ? " " : appState.streamingSummary)
                            .font(.system(size: 12))
                            .foregroundColor(.primary.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                            .id("streamingText")
                    }
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .padding(.horizontal, 12)
                    .onChange(of: appState.streamingSummary) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("streamingText", anchor: .bottom)
                        }
                    }
                }
            }

            // Streaming translation text below waveform (during translation)
            if appState.isTranslating || !appState.streamingTranslation.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(appState.streamingTranslation.isEmpty ? " " : appState.streamingTranslation)
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.3, green: 0.55, blue: 0.85))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                            .id("streamingTranslation")
                    }
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.3, green: 0.55, blue: 0.85).opacity(0.08))
                    .cornerRadius(6)
                    .padding(.horizontal, 12)
                    .onChange(of: appState.streamingTranslation) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("streamingTranslation", anchor: .bottom)
                        }
                    }
                }
            }

            // Speed control row
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Slider(
                    value: Binding(
                        get: { appState.playbackSpeed },
                        set: { appState.updatePlaybackSpeed($0) }
                    ),
                    in: 1.0...2.5,
                    step: 0.1
                )
                .controlSize(.small)
                
                Text(String(format: "%.1fx", appState.playbackSpeed))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 16)

            // Bottom row: voice info and controls
            HStack {
                // Voice indicator or summarizing/translating status
                HStack(spacing: 6) {
                    if appState.isSummarizing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)

                        Text("Summarizing...")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    } else if appState.isTranslating {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)

                        Text("Translating...")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.3, green: 0.55, blue: 0.85))
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Text(voiceDisplayName)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                // Control buttons
                HStack(spacing: 8) {
                    Button(action: { appState.stopPlayback() }) {
                        HStack(spacing: 4) {
                            Text("Stop")
                            Text("⌥")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)

                    Button(action: { appState.stopPlayback() }) {
                        HStack(spacing: 4) {
                            Text("Cancel")
                            Text("esc")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var voiceDisplayName: String {
        // Capitalize the voice name
        appState.selectedVoice.capitalized
    }
}

#Preview {
    AudioPlayerPanel(audioLevelMonitor: AudioLevelMonitor())
        .environmentObject(AppState.shared)
        .padding()
}
