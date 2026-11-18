import Foundation

/// Usage totals for one calendar day.
struct DayUsageTotals: Codable, Sendable, Equatable {
    var cost: Double = 0
    var ttsCost: Double = 0
    var llmCost: Double = 0
    var translationCost: Double = 0
    var wordCount: Int = 0
    var audioSeconds: Double = 0
    var requestCount: Int = 0

    static let zero = DayUsageTotals()

    mutating func add(_ other: DayUsageTotals) {
        cost += other.cost
        ttsCost += other.ttsCost
        llmCost += other.llmCost
        translationCost += other.translationCost
        wordCount += other.wordCount
        audioSeconds += other.audioSeconds
        requestCount += other.requestCount
    }

    /// - Parameter audioByteCount: size of the entry's PCM audio (24kHz 16-bit mono = 48000 bytes/second).
    init(entry: HistoryEntry, audioByteCount: Int) {
        cost = entry.cost
        ttsCost = entry.ttsCost
        llmCost = entry.llmCost ?? 0
        translationCost = entry.translationCost ?? 0
        wordCount = entry.wordCount
        audioSeconds = Double(audioByteCount) / 48_000.0
        requestCount = 1
    }

    init() {}
}

/// Running per-day usage totals, stored apart from the history.
///
/// History is pruned by the retention policy (7 days by default) and by the user deleting
/// entries, so statistics derived from it silently forgot everything older: "This Month"
/// and "All Time" really meant "what is still in history". Money already spent does not
/// come back when an entry is pruned, so each request is added here once and never removed.
///
/// Not thread-safe: use from the main thread, like `HistoryManager.entries`.
final class UsageLedger {
    static let shared = UsageLedger(
        fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hibiki", isDirectory: true)
            .appendingPathComponent("usage-ledger.json")
    )

    private let fileURL: URL
    private let calendar: Calendar
    /// Totals keyed by local calendar day, "yyyy-MM-dd".
    private var totalsByDay: [String: DayUsageTotals] = [:]
    private(set) var existsOnDisk: Bool

    /// `autoupdatingCurrent`: a menu bar app runs for days, across time zone changes. A
    /// calendar captured once would keep bucketing by the old zone.
    init(fileURL: URL, calendar: Calendar = .autoupdatingCurrent) {
        self.fileURL = fileURL
        self.calendar = calendar
        existsOnDisk = FileManager.default.fileExists(atPath: fileURL.path)
        load()
    }

    /// Add one finished request to its day's totals.
    func record(entry: HistoryEntry, audioByteCount: Int) {
        add(DayUsageTotals(entry: entry, audioByteCount: audioByteCount), on: entry.timestamp)
        save()
    }

    /// First launch with a ledger: start from what the history still holds.
    /// Does nothing once a ledger file exists, so entries are never counted twice.
    func seedIfNeeded(from entries: [HistoryEntry], audioByteCount: (HistoryEntry) -> Int) {
        guard !existsOnDisk else { return }
        for entry in entries {
            add(DayUsageTotals(entry: entry, audioByteCount: audioByteCount(entry)), on: entry.timestamp)
        }
        save()
    }

    /// Totals keyed by the start of each local day.
    func snapshot() -> [Date: DayUsageTotals] {
        var result: [Date: DayUsageTotals] = [:]
        for (key, totals) in totalsByDay {
            guard let day = date(fromKey: key) else { continue }
            result[day, default: .zero].add(totals)
        }
        return result
    }

    private func add(_ totals: DayUsageTotals, on date: Date) {
        totalsByDay[key(for: date), default: .zero].add(totals)
    }

    private func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func load() {
        guard existsOnDisk else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            totalsByDay = try JSONDecoder().decode([String: DayUsageTotals].self, from: data)
        } catch {
            // Keep the unreadable file for inspection rather than overwriting it on the next save.
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            existsOnDisk = false  // re-seed from history
            print("[Hibiki] Failed to load usage ledger (\(error)); moved it to \(backup.lastPathComponent)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(totalsByDay).write(to: fileURL, options: .atomic)
            existsOnDisk = true
        } catch {
            print("[Hibiki] Failed to save usage ledger: \(error)")
        }
    }
}
