import SwiftUI

struct AudioPlayerPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioLevelMonitor: AudioLevelMonitor

    var body: some View {
        if appState.isPanelCollapsed {
            collapsedView
        } else {
            expandedView
        }
    }

    // MARK: - Collapsed View

    private var collapsedView: some View {
        HStack(spacing: 8) {
            // Small waveform indicator
            WaveformView(level: audioLevelMonitor.currentLevel, barCount: 8)
                .frame(width: 40, height: 20)

            // Status indicator
            if appState.isSummarizing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Summarizing...")
                    .font(.system(size: 11))
                    .lineLimit(1)
            } else if appState.isTranslating {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Translating...")
                    .font(.system(size: 11))
                    .lineLimit(1)
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Playing...")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }

            Spacer()

            // Expand button
            Button(action: { appState.isPanelCollapsed = false }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            // Stop button
            Button(action: { appState.stopPlayback() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 200)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Expanded View

    private var expandedView: some View {
        VStack(spacing: 8) {
            // Header with collapse button
            HStack {
                Spacer()
                Button(action: { appState.isPanelCollapsed = true }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Collapse panel")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Waveform visualization (always shown)
            WaveformView(level: audioLevelMonitor.currentLevel, barCount: 50)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

            // Text display with highlighting
            // Priority:
            // 1. During active translation (LLM streaming): show streaming translation
            // 2. During active summarization (LLM streaming): show streaming summary
            // 3. During TTS playback (including after summarization/translation): show highlighted text
            if appState.isTranslating {
                // Streaming translation text (during active translation)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(appState.streamingTranslation.isEmpty ? " " : appState.streamingTranslation)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
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
            } else if appState.isSummarizing {
                // Streaming summary text (during active summarization)
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
            } else if appState.isPlaying && !appState.displayText.isEmpty {
                // Highlighted text during TTS playback (direct TTS, or after summarization/translation)
                HighlightedTextView(
                    text: appState.displayText,
                    highlightIndex: appState.highlightCharacterIndex,
                    highlightColor: highlightColorForMode
                )
                .frame(height: 80)
                .frame(maxWidth: .infinity)
                .background(backgroundColorForMode)
                .cornerRadius(6)
                .padding(.horizontal, 12)
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
                            .foregroundColor(.primary)
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

    /// Highlight color based on playback mode
    private var highlightColorForMode: Color {
        // Check if this was a translation or summarization based on the content
        if !appState.streamingTranslation.isEmpty {
            return Color(red: 0.3, green: 0.55, blue: 0.85)  // Blue for translation
        } else if !appState.streamingSummary.isEmpty {
            return .orange  // Orange for summary
        }
        return .accentColor  // Default for direct TTS
    }

    /// Background color for the text view based on playback mode
    private var backgroundColorForMode: Color {
        if !appState.streamingTranslation.isEmpty {
            return Color(red: 0.3, green: 0.55, blue: 0.85).opacity(0.08)
        } else if !appState.streamingSummary.isEmpty {
            return Color.primary.opacity(0.05)
        }
        return Color.primary.opacity(0.05)  // Default
    }
}

#Preview {
    AudioPlayerPanel(audioLevelMonitor: AudioLevelMonitor())
        .environmentObject(AppState.shared)
        .padding()
}
