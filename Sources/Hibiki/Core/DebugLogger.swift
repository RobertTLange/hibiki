import Foundation
import SwiftUI

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    let source: String

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Debug logger - NOT @Observable to avoid threading conflicts with SwiftUI observation.
/// Views should maintain their own @State for entries and call refresh methods.
final class DebugLogger {
    static let shared = DebugLogger()

    /// Thread-safe access to entries. Always access from main thread.
    private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    private init() {}

    func log(_ message: String, level: LogLevel = .info, source: String = "Hibiki") {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            source: source
        )

        // Also print to console for Xcode debugging
        print("[Hibiki] [\(level.rawValue)] [\(source)] \(message)")

        DispatchQueue.main.async {
            self.entries.append(entry)

            // Trim old entries if exceeding max
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func debug(_ message: String, source: String = "Hibiki") {
        log(message, level: .debug, source: source)
    }

    func info(_ message: String, source: String = "Hibiki") {
        log(message, level: .info, source: source)
    }

    func warning(_ message: String, source: String = "Hibiki") {
        log(message, level: .warning, source: source)
    }

    func error(_ message: String, source: String = "Hibiki") {
        log(message, level: .error, source: source)
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }
}
