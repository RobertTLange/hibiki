import SwiftUI
import AppKit

/// Manages playback state for history replay with proper lifecycle handling
final class HistoryPlaybackManager: ObservableObject {
    static let shared = HistoryPlaybackManager()

    @Published var playingEntryId: UUID?
    @Published var playbackProgress: Double = 0.0

    private var progressTimer: Timer?
    private var playbackStartTime: Date?
    private var seekOffset: TimeInterval = 0
    private var currentAudioData: Data?
    private var currentDuration: TimeInterval = 0
    private let audioPlayer = StreamingAudioPlayer.shared

    private init() {}

    func replay(entry: HistoryEntry, audioData: Data) {
        // If already playing this entry, stop it
        if playingEntryId == entry.id {
            stop()
            return
        }

        // Stop any current playback
        stop()

        // Set up state
        playingEntryId = entry.id
        currentAudioData = audioData
        currentDuration = Double(audioData.count) / 48000.0
        playbackProgress = 0.0
        seekOffset = 0
        audioPlayer.reset()

        // Start playback from the beginning
        playFromOffset(0)

        // Start progress tracking
        startProgressTracking(entryId: entry.id)
    }

    func seek(to progress: Double) {
        guard currentAudioData != nil else { return }

        let seekTime = currentDuration * progress

        // Calculate byte offset (2 bytes per sample at 24kHz)
        let byteOffset = Int(seekTime * 48000.0)
        // Align to frame boundary (2 bytes per frame for 16-bit mono)
        let alignedOffset = (byteOffset / 2) * 2

        // Stop current playback
        audioPlayer.stop()
        audioPlayer.reset()

        // Update seek offset and restart progress tracking
        seekOffset = seekTime
        playbackStartTime = Date()
        playbackProgress = progress

        // Play from new offset
        playFromOffset(alignedOffset)
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer.stop()
        audioPlayer.onPlaybackComplete = nil
        playingEntryId = nil
        playbackProgress = 0.0
        playbackStartTime = nil
        seekOffset = 0
        currentAudioData = nil
        currentDuration = 0
    }

    private func playFromOffset(_ offset: Int) {
        guard let audioData = currentAudioData else { return }

        // Enqueue the audio data from the specified byte offset in chunks
        let chunkSize = 8192
        var currentOffset = offset
        while currentOffset < audioData.count {
            let end = min(currentOffset + chunkSize, audioData.count)
            let chunk = audioData[currentOffset..<end]
            audioPlayer.enqueue(pcmData: Data(chunk))
            currentOffset = end
        }

        // Mark stream complete to trigger natural playback completion
        audioPlayer.markStreamComplete()
    }

    private func startProgressTracking(entryId: UUID) {
        playbackStartTime = Date()

        // Set up completion callback
        audioPlayer.onPlaybackComplete = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.playingEntryId == entryId else { return }
                self.stop()
            }
        }

        // Start timer for progress updates
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.playbackStartTime,
                  self.playingEntryId == entryId,
                  self.currentDuration > 0 else { return }

            let elapsed = Date().timeIntervalSince(startTime) + self.seekOffset
            let progress = min(1.0, max(0.0, elapsed / self.currentDuration))

            DispatchQueue.main.async {
                self.playbackProgress = progress

                // Check if playback has finished
                if progress >= 1.0 {
                    self.stop()
                }
            }
        }
    }
}

struct HistoryTab: View {
    private let historyManager = HistoryManager.shared
    @StateObject private var playbackManager = HistoryPlaybackManager.shared
    @State private var audioDurations: [UUID: TimeInterval] = [:]

    // Local copy of entries to avoid observation issues
    @State private var entries: [HistoryEntry] = []
    @State private var totalCost: String = "$0.000000"
    @State private var selectedEntries: Set<HistoryEntry.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TTS History")
                    .font(.headline)

                Text("(\(entries.count) entries)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !selectedEntries.isEmpty {
                    Button("Copy Selected") {
                        copySelectedEntries()
                    }
                    .controlSize(.small)
                }

                Button("Clear All") {
                    playbackManager.stop()
                    historyManager.clearAllHistory()
                    refreshEntries()
                }
                .disabled(entries.isEmpty)
            }
            .padding()

            Divider()

            // Table or empty state
            if entries.isEmpty {
                emptyStateView
            } else {
                HistoryTableView(
                    entries: entries,
                    selection: $selectedEntries,
                    playingEntryId: $playbackManager.playingEntryId,
                    playbackProgress: $playbackManager.playbackProgress,
                    audioDurations: audioDurations,
                    onReplay: replayEntry,
                    onDelete: deleteEntry,
                    onSeek: seekToPosition
                )
                .onCopyCommand {
                    copySelectedEntries()
                    return selectedItemProviders()
                }
            }

            Divider()

            // Footer with total cost
            HStack {
                Text("Total cost: \(totalCost)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if playbackManager.playingEntryId != nil {
                    Button("Stop") {
                        playbackManager.stop()
                    }
                    .controlSize(.small)
                }
            }
            .padding()
        }
        .onAppear {
            refreshEntries()
        }
    }

    private func refreshEntries() {
        entries = historyManager.entries
        totalCost = historyManager.formattedTotalCost
        // Calculate audio durations for all entries
        for entry in entries {
            if audioDurations[entry.id] == nil {
                if let duration = historyManager.audioDuration(for: entry) {
                    audioDurations[entry.id] = duration
                }
            }
        }
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
        // Get audio data and play
        guard let audioData = historyManager.getAudioData(for: entry) else {
            print("[Hibiki] Failed to load audio for history entry")
            return
        }

        playbackManager.replay(entry: entry, audioData: audioData)
    }

    private func seekToPosition(_ entry: HistoryEntry, _ progress: Double) {
        guard playbackManager.playingEntryId == entry.id else { return }
        playbackManager.seek(to: progress)
    }

    private func deleteEntry(_ entry: HistoryEntry) {
        if playbackManager.playingEntryId == entry.id {
            playbackManager.stop()
        }
        historyManager.deleteEntry(entry)
        refreshEntries()
    }

    private func copySelectedEntries() {
        let selected = entries.filter { selectedEntries.contains($0.id) }
        guard !selected.isEmpty else { return }

        let text = selected.map { entry in
            formatEntryForCopy(entry)
        }.joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func selectedItemProviders() -> [NSItemProvider] {
        let selected = entries.filter { selectedEntries.contains($0.id) }
        guard !selected.isEmpty else { return [] }

        let text = selected.map { entry in
            formatEntryForCopy(entry)
        }.joined(separator: "\n\n---\n\n")

        return [NSItemProvider(object: text as NSString)]
    }

    private func formatEntryForCopy(_ entry: HistoryEntry) -> String {
        var lines: [String] = []
        lines.append("[\(entry.formattedTimestamp)]")
        lines.append("Original: \(entry.text)")

        if let summary = entry.summarizedText {
            lines.append("Summary: \(summary)")
        }

        if let translation = entry.translatedText {
            let lang = entry.targetLanguageDisplayName ?? entry.targetLanguage ?? "Unknown"
            lines.append("Translation (\(lang)): \(translation)")
        }

        return lines.joined(separator: "\n")
    }
}
