import SwiftUI

struct AudioPlayerPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioLevelMonitor: AudioLevelMonitor

    var body: some View {
        VStack(spacing: 12) {
            // Waveform visualization
            WaveformView(level: audioLevelMonitor.currentLevel, barCount: 50)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Bottom row: voice info and controls
            HStack {
                // Voice indicator
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Text(voiceDisplayName)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                }

                Spacer()

                // Control buttons
                HStack(spacing: 8) {
                    Button(action: { appState.stopPlayback() }) {
                        HStack(spacing: 4) {
                            Text("Stop")
                            Text("S")
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
