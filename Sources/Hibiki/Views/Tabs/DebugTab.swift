import SwiftUI
import AppKit

struct DebugTab: View {
    private let logger = DebugLogger.shared

    // Local copy of entries to avoid observation issues
    @State private var entries: [LogEntry] = []
    @State private var selectedEntries: Set<LogEntry.ID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Debug Logs")
                    .font(.headline)

                Text("(\(entries.count) entries)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !selectedEntries.isEmpty {
                    Button("Copy Selected") {
                        copySelectedEntries()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Clear") {
                    logger.clear()
                    refreshEntries()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()

            Divider()

            // Content
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "ladybug")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Log Entries")
                        .font(.headline)

                    Text("Trigger some actions to see logs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DebugLogTableView(entries: entries, selection: $selectedEntries)
                    .onCopyCommand {
                        copySelectedEntries()
                        return selectedItemProviders()
                    }
            }
        }
        .onAppear {
            refreshEntries()
        }
    }

    private func refreshEntries() {
        entries = logger.entries
    }

    private func copySelectedEntries() {
        let selectedLogs = entries.filter { selectedEntries.contains($0.id) }
        guard !selectedLogs.isEmpty else { return }

        let text = selectedLogs.map { entry in
            "[\(entry.formattedTime)] [\(entry.level.rawValue)] [\(entry.source)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func selectedItemProviders() -> [NSItemProvider] {
        let selectedLogs = entries.filter { selectedEntries.contains($0.id) }
        guard !selectedLogs.isEmpty else { return [] }

        let text = selectedLogs.map { entry in
            "[\(entry.formattedTime)] [\(entry.level.rawValue)] [\(entry.source)] \(entry.message)"
        }.joined(separator: "\n")

        return [NSItemProvider(object: text as NSString)]
    }
}
