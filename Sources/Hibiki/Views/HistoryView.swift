import SwiftUI

struct HistoryView: View {
    @State private var historyManager = HistoryManager.shared
    @State private var playingEntryId: UUID?
    private let audioPlayer = StreamingAudioPlayer.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TTS History")
                    .font(.headline)

                Text("(\(historyManager.entries.count) entries)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Clear All") {
                    stopPlayback()
                    historyManager.clearAllHistory()
                }
                .disabled(historyManager.entries.isEmpty)
            }
            .padding()

            Divider()

            // Table or empty state
            if historyManager.entries.isEmpty {
                emptyStateView
            } else {
                HistoryTableView(
                    entries: historyManager.entries,
                    playingEntryId: $playingEntryId,
                    onReplay: replayEntry,
                    onDelete: deleteEntry
                )
            }

            Divider()

            // Footer with total cost
            HStack {
                Text("Total cost: \(historyManager.formattedTotalCost)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if playingEntryId != nil {
                    Button("Stop") {
                        stopPlayback()
                    }
                    .controlSize(.small)
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No History Yet")
                .font(.headline)

            Text("Use the hotkey to speak text.\nIt will appear here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func replayEntry(_ entry: HistoryEntry) {
        // If already playing this entry, stop it
        if playingEntryId == entry.id {
            stopPlayback()
            return
        }

        // Stop any current playback
        stopPlayback()

        // Get audio data and play
        guard let audioData = historyManager.getAudioData(for: entry) else {
            print("[Hibiki] Failed to load audio for history entry")
            return
        }

        playingEntryId = entry.id
        audioPlayer.reset()

        // Enqueue the audio data in chunks for smooth playback
        let chunkSize = 8192
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + chunkSize, audioData.count)
            let chunk = audioData[offset..<end]
            audioPlayer.enqueue(pcmData: Data(chunk))
            offset = end
        }

        // Estimate duration and reset state when done
        // Duration = bytes / (sampleRate * bytesPerSample)
        // 24kHz, 16-bit mono = 24000 * 2 = 48000 bytes/second
        let durationSeconds = Double(audioData.count) / 48000.0

        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds + 0.5) { [self] in
            if self.playingEntryId == entry.id {
                self.playingEntryId = nil
            }
        }
    }

    private func deleteEntry(_ entry: HistoryEntry) {
        if playingEntryId == entry.id {
            stopPlayback()
        }
        historyManager.deleteEntry(entry)
    }

    private func stopPlayback() {
        audioPlayer.stop()
        playingEntryId = nil
    }
}
