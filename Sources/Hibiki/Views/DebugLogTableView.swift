import SwiftUI
import AppKit

struct DebugLogTableView: View {
    let entries: [LogEntry]
    @Binding var selection: Set<LogEntry.ID>

    var body: some View {
        Table(entries, selection: $selection) {
            TableColumn("Time") { entry in
                Text(entry.formattedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(80)

            TableColumn("Level") { entry in
                LogLevelBadge(level: entry.level)
            }
            .width(60)

            TableColumn("Source") { entry in
                Text(entry.source)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(70)

            TableColumn("Message") { entry in
                HoverableLogCell(
                    entry: entry,
                    displayText: truncateText(entry.message, maxLength: 100)
                )
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: LogEntry.ID.self) { selectedIds in
            Button("Copy") {
                copyEntries(ids: selectedIds)
            }
            .keyboardShortcut("c", modifiers: .command)
        } primaryAction: { _ in
            // Double-click action (optional)
        }
    }

    private func truncateText(_ text: String, maxLength: Int) -> String {
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }

    private func copyEntries(ids: Set<LogEntry.ID>) {
        let selectedLogs = entries.filter { ids.contains($0.id) }
        guard !selectedLogs.isEmpty else { return }

        let text = selectedLogs.map { entry in
            "[\(entry.formattedTime)] [\(entry.level.rawValue)] [\(entry.source)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A hoverable cell for log messages that shows full text on hover
struct HoverableLogCell: View {
    let entry: LogEntry
    let displayText: String

    @State private var isHovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Text(displayText)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hovering in
                isHovering = hovering
                if hovering && entry.message.count > 100 {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if !Task.isCancelled && isHovering {
                            await MainActor.run {
                                showPopover = true
                            }
                        }
                    }
                } else {
                    hoverTask?.cancel()
                    hoverTask = nil
                    showPopover = false
                }
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Log Message")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(entry.message.count) chars")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading) {
                            Text(entry.message)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(nil)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(width: 450, alignment: .leading)
                    }
                    .frame(width: 465, height: min(max(CGFloat(entry.message.count) / 3, 60), 300))
                }
                .padding(12)
                .frame(width: 490)
            }
    }
}

struct LogLevelBadge: View {
    let level: LogLevel

    var body: some View {
        Text(level.rawValue)
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.medium)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(3)
    }

    private var backgroundColor: Color {
        switch level {
        case .debug: return .gray.opacity(0.2)
        case .info: return .blue.opacity(0.2)
        case .warning: return .orange.opacity(0.2)
        case .error: return .red.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
