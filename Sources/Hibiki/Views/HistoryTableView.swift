import SwiftUI
import AppKit

struct HistoryTableView: View {
    let entries: [HistoryEntry]
    @Binding var selection: Set<HistoryEntry.ID>
    @Binding var playingEntryId: UUID?
    @Binding var playbackProgress: Double
    let audioDurations: [UUID: TimeInterval]
    let onReplay: (HistoryEntry) -> Void
    let onDelete: (HistoryEntry) -> Void
    let onSeek: (HistoryEntry, Double) -> Void

    var body: some View {
        Table(entries, selection: $selection) {
            TableColumn("Time") { entry in
                Text(entry.formattedTimestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 120, ideal: 140)

            TableColumn("Type / Provider") { entry in
                HStack(spacing: 4) {
                    // Type icons
                    HStack(spacing: 2) {
                        if entry.wasSummarized {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                                .font(.caption2)
                        }
                        if entry.wasTranslated {
                            Image(systemName: "globe")
                                .foregroundColor(Color(red: 0.3, green: 0.55, blue: 0.85))
                                .font(.caption2)
                        }
                        if !entry.wasSummarized && !entry.wasTranslated {
                            Image(systemName: "speaker.wave.2")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                    }
                    // Duration
                    if let duration = audioDurations[entry.id] {
                        Text(HistoryEntry.formatDuration(duration))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text(entry.ttsProviderDisplayName)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(entry.ttsProvider == .elevenLabs ? Color(red: 0.3, green: 0.55, blue: 0.85) : .secondary)
                }
                .help(typeHelp(for: entry))
            }
            .width(min: 120, ideal: 135)

            TableColumn("Original Text") { entry in
                HoverableTextCell(
                    text: entry.text,
                    displayText: truncateText(entry.text, maxLength: 80),
                    title: "Original Text"
                )
            }
            .width(min: 120, ideal: 180)
            
            TableColumn("Summary") { entry in
                if let summary = entry.summarizedText {
                    HoverableTextCell(
                        text: summary,
                        displayText: truncateText(summary, maxLength: 60),
                        title: "Summary",
                        textColor: .purple
                    )
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("Translation") { entry in
                if let translation = entry.translatedText {
                    HoverableTextCell(
                        text: translation,
                        displayText: truncateText(translation, maxLength: 60),
                        title: "Translation (\(entry.targetLanguageDisplayName ?? ""))",
                        textColor: Color(red: 0.3, green: 0.55, blue: 0.85)
                    )
                } else {
                    Text("-")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 100, ideal: 140)

            TableColumn("LLM") { entry in
                Text(entry.formattedLLMCost)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(entry.wasSummarized ? .orange : .secondary)
            }
            .width(55)

            TableColumn("Translate") { entry in
                Text(entry.formattedTranslationCost)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(entry.wasTranslated ? Color(red: 0.3, green: 0.55, blue: 0.85) : .secondary)
            }
            .width(55)

            TableColumn("TTS") { entry in
                Text(entry.formattedTTSCost)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.purple)
            }
            .width(60)
            
            TableColumn("Total") { entry in
                Text(entry.formattedCost)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue)
            }
            .width(65)

            TableColumn("Actions") { entry in
                let isPlaying = playingEntryId == entry.id
                let duration = audioDurations[entry.id] ?? 0

                HStack(spacing: 6) {
                    Button {
                        onReplay(entry)
                    } label: {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .foregroundColor(isPlaying ? .red : .accentColor)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help(isPlaying ? "Stop" : "Replay")

                    if isPlaying && duration > 0 {
                        // Show progress bar with seek functionality
                        PlaybackProgressView(
                            progress: playbackProgress,
                            duration: duration,
                            onSeek: { progress in
                                onSeek(entry, progress)
                            }
                        )
                        .frame(width: 80)
                    }

                    Button {
                        onDelete(entry)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
            .width(min: 80, ideal: 140)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: HistoryEntry.ID.self) { selectedIds in
            Button("Copy") {
                copyEntries(ids: selectedIds)
            }
            .keyboardShortcut("c", modifiers: .command)

            Divider()

            Button("Delete", role: .destructive) {
                for id in selectedIds {
                    if let entry = entries.first(where: { $0.id == id }) {
                        onDelete(entry)
                    }
                }
            }
        } primaryAction: { selectedIds in
            // Double-click plays the entry
            if let id = selectedIds.first,
               let entry = entries.first(where: { $0.id == id }) {
                onReplay(entry)
            }
        }
    }

    private func copyEntries(ids: Set<HistoryEntry.ID>) {
        let selected = entries.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }

        let text = selected.map { entry in
            formatEntryForCopy(entry)
        }.joined(separator: "\n\n---\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
    
    /// Truncate text to a maximum length with ellipsis
    private func truncateText(_ text: String, maxLength: Int) -> String {
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }

    /// Generate help text for the type column
    private func typeHelp(for entry: HistoryEntry) -> String {
        var parts: [String] = []
        if entry.wasSummarized {
            parts.append("Summarized")
        }
        if entry.wasTranslated {
            if let lang = entry.targetLanguageDisplayName {
                parts.append("Translated to \(lang)")
            } else {
                parts.append("Translated")
            }
        }
        if parts.isEmpty {
            return "Direct text-to-speech"
        }
        return parts.joined(separator: " + ") + " before TTS"
    }
}

/// A progress bar for audio playback with seek functionality
struct PlaybackProgressView: View {
    let progress: Double
    let duration: TimeInterval
    let onSeek: (Double) -> Void

    @State private var isHovering = false
    @State private var hoverProgress: Double = 0

    var body: some View {
        VStack(spacing: 2) {
            // Progress bar with seek functionality
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))

                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * CGFloat(progress))

                    // Hover indicator
                    if isHovering {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(width: geometry.size.width * CGFloat(hoverProgress))
                    }
                }
                .frame(height: 6)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newProgress = min(1.0, max(0.0, value.location.x / geometry.size.width))
                            hoverProgress = newProgress
                        }
                        .onEnded { value in
                            let seekProgress = min(1.0, max(0.0, value.location.x / geometry.size.width))
                            onSeek(seekProgress)
                        }
                )
                .onHover { hovering in
                    isHovering = hovering
                    if !hovering {
                        hoverProgress = 0
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverProgress = min(1.0, max(0.0, location.x / geometry.size.width))
                    case .ended:
                        hoverProgress = 0
                    }
                }
            }
            .frame(height: 6)

            // Time display
            HStack(spacing: 0) {
                Text(HistoryEntry.formatDuration(duration * progress))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(" / ")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.6))
                Text(HistoryEntry.formatDuration(duration))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .help("Click or drag to seek")
    }
}

/// A text cell that shows a popover with full text on hover
struct HoverableTextCell: View {
    let text: String
    let displayText: String
    var title: String = ""
    var textColor: Color = .primary
    
    @State private var isHovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?
    
    var body: some View {
        Text(displayText)
            .font(.system(.caption))
            .lineLimit(2)
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    // Start a delayed task to show popover
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                        if !Task.isCancelled && isHovering {
                            await MainActor.run {
                                showPopover = true
                            }
                        }
                    }
                } else {
                    // Cancel pending task and hide popover
                    hoverTask?.cancel()
                    hoverTask = nil
                    showPopover = false
                }
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    if !title.isEmpty {
                        HStack {
                            Text(title)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(text.count) chars")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading) {
                            Text(text)
                                .font(.system(size: 13))
                                .lineLimit(nil)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(width: 380, alignment: .leading)
                    }
                    .frame(width: 395, height: min(max(CGFloat(text.count) / 2.5, 80), 350))
                }
                .padding(12)
                .frame(width: 420)
            }
    }
}
