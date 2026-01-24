import SwiftUI

struct HistoryTableView: View {
    let entries: [HistoryEntry]
    @Binding var playingEntryId: UUID?
    let onReplay: (HistoryEntry) -> Void
    let onDelete: (HistoryEntry) -> Void

    var body: some View {
        Table(entries) {
            TableColumn("Time") { entry in
                Text(entry.formattedTimestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 120, ideal: 140)

            TableColumn("Type") { entry in
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
                .help(typeHelp(for: entry))
            }
            .width(50)

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
                HStack(spacing: 8) {
                    Button {
                        onReplay(entry)
                    } label: {
                        Image(systemName: playingEntryId == entry.id ? "stop.fill" : "play.fill")
                            .foregroundColor(playingEntryId == entry.id ? .red : .accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help(playingEntryId == entry.id ? "Stop" : "Replay")

                    Button {
                        onDelete(entry)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
            .width(60)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
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
