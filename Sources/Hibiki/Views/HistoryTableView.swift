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

            TableColumn("Text") { entry in
                Text(entry.truncatedText)
                    .font(.system(.caption))
                    .lineLimit(2)
                    .help(entry.text)
            }
            .width(min: 200, ideal: 300)

            TableColumn("Voice") { entry in
                Text(entry.voice.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .width(60)

            TableColumn("Cost") { entry in
                Text(entry.formattedCost)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(60)

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
            .width(80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}
