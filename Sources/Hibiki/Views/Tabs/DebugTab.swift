import SwiftUI

struct DebugTab: View {
    private let logger = DebugLogger.shared

    // Local copy of entries to avoid observation issues
    @State private var entries: [LogEntry] = []

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
                DebugLogTableView(entries: entries)
            }
        }
        .onAppear {
            refreshEntries()
        }
    }

    private func refreshEntries() {
        entries = logger.entries
    }
}
