import SwiftUI
import Combine
import AppKit

/// History tab's view of replay state. Playback itself is owned by `AppState`, the single
/// owner of the shared audio player, so a replay and live speech cannot fight over it.
@MainActor
final class HistoryPlaybackManager: ObservableObject {
    static let shared = HistoryPlaybackManager()

    @Published var playingEntryId: UUID?
    @Published var playbackProgress: Double = 0.0

    private let appState = AppState.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        appState.$activeHistoryReplayEntryId
            .removeDuplicates()
            .sink { [weak self] entryID in
                self?.playingEntryId = entryID
                if entryID == nil {
                    self?.playbackProgress = 0.0
                }
            }
            .store(in: &cancellables)

        // AppState publishes progress at display rate for every playback; the table only
        // needs it for replays, and not that often.
        appState.$playbackProgress
            .throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] progress in
                guard let self, self.playingEntryId != nil else { return }
                self.playbackProgress = progress
            }
            .store(in: &cancellables)
    }

    func replay(entry: HistoryEntry) {
        appState.toggleHistoryReplay(for: entry)
    }

    func seek(entry: HistoryEntry, to progress: Double) {
        appState.seekHistoryReplay(for: entry, to: progress)
    }

    /// Stops the replay; live speech is left alone.
    func stop() {
        guard appState.activeHistoryReplayEntryId != nil else { return }
        appState.stopPlayback()
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
        playbackManager.replay(entry: entry)
    }

    private func seekToPosition(_ entry: HistoryEntry, _ progress: Double) {
        playbackManager.seek(entry: entry, to: progress)
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
