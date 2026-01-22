import SwiftUI

struct DebugLogTableView: View {
    let entries: [LogEntry]

    var body: some View {
        Table(entries) {
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
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
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
