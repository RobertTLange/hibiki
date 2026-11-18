import Foundation
import Combine

/// History manager - NOT @Observable to avoid threading conflicts with SwiftUI observation.
/// Views should maintain their own @State for entries and call refresh methods.
final class HistoryManager {
    static let shared = HistoryManager()

    static let retentionDaysDefaultsKey = "historyRetentionDays"
    static let maxEntriesDefaultsKey = "historyRetentionMaxEntries"
    static let maxDiskSpaceDefaultsKey = "historyRetentionMaxDiskSpaceMB"
    static let defaultRetentionDays = 7
    static let defaultMaxEntries = 50_000
    static let defaultMaxDiskSpaceMB: Double = 10_000
    static let minRetentionDays = 1
    static let maxRetentionDays = 365
    static let minMaxEntries = 10
    static let maxMaxEntries = 1_000_000
    static let minMaxDiskSpaceMB: Double = 100
    static let maxMaxDiskSpaceMB: Double = 250_000
    static let retentionSettingsMigrationVersionKey = "historyRetentionSettingsMigrationVersion"
    static let retentionSettingsMigrationVersion = 1
    private static let legacyDefaultMaxEntriesV0 = 100
    private static let legacyDefaultMaxEntriesV1 = 1000
    
    /// Publisher that emits when entries change (add, delete, clear)
    let entriesDidChange = PassthroughSubject<Void, Never>()

    /// Thread-safe access to entries. Always access from main thread.
    private(set) var entries: [HistoryEntry] = []

    private let fileIOQueue = DispatchQueue(label: "com.hibiki.history.fileio", qos: .utility)

    private var appSupportDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Hibiki", isDirectory: true)
    }

    private var historyFile: URL {
        appSupportDirectory.appendingPathComponent("history.json")
    }

    var audioDirectory: URL {
        appSupportDirectory.appendingPathComponent("audio", isDirectory: true)
    }

    private init() {
        migrateRetentionSettingsIfNeeded()
        ensureDirectoriesExist()
        loadHistory()
        // Before pruning: seed the usage ledger with everything history still remembers.
        UsageLedger.shared.seedIfNeeded(from: entries) { [self] entry in
            Int(audioFileSize(for: entry) ?? 0)
        }
        let previousCount = entries.count
        enforceRetentionPolicy()
        if entries.count != previousCount {
            saveHistory()
        }
    }

    // MARK: - Public API

    @discardableResult
    func addEntry(
        text: String,
        voice: String,
        inputTokens: Int,
        ttsBilling: TTSBilling,
        audioData: Data,
        summarizedText: String? = nil,
        llmInputTokens: Int? = nil,
        llmOutputTokens: Int? = nil,
        llmModel: String? = nil,
        translatedText: String? = nil,
        translationInputTokens: Int? = nil,
        translationOutputTokens: Int? = nil,
        translationModel: String? = nil,
        targetLanguage: String? = nil
    ) -> HistoryEntry {
        let audioFileName = "\(UUID().uuidString).pcm"
        let audioURL = audioDirectory.appendingPathComponent(audioFileName)

        let entry = HistoryEntry(
            text: text,
            voice: voice,
            inputTokens: inputTokens,
            audioFileName: audioFileName,
            ttsCost: TTSPricing.cost(
                billing: ttsBilling,
                inputTokens: inputTokens,
                audioSeconds: Double(audioData.count) / 48_000.0  // 24kHz 16-bit mono
            ),
            summarizedText: summarizedText,
            llmInputTokens: llmInputTokens,
            llmOutputTokens: llmOutputTokens,
            llmModel: llmModel,
            translatedText: translatedText,
            translationInputTokens: translationInputTokens,
            translationOutputTokens: translationOutputTokens,
            translationModel: translationModel,
            targetLanguage: targetLanguage
        )

        // Save audio file off the main thread to avoid UI stalls
        fileIOQueue.async {
            do {
                try audioData.write(to: audioURL)
            } catch {
                print("[Hibiki] Failed to save audio file: \(error)")
            }
        }

        DispatchQueue.main.async {
            UsageLedger.shared.record(entry: entry, audioByteCount: audioData.count)
            self.entries.insert(entry, at: 0)
            self.enforceRetentionPolicy()
            self.saveHistory()
            self.entriesDidChange.send()
        }

        return entry
    }

    func deleteEntry(_ entry: HistoryEntry) {
        // Delete audio file
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        fileIOQueue.async {
            try? FileManager.default.removeItem(at: audioURL)
        }

        DispatchQueue.main.async {
            self.entries.removeAll { $0.id == entry.id }
            self.saveHistory()
            self.entriesDidChange.send()
        }
    }

    func clearAllHistory() {
        // Delete all audio files
        let audioURLs = entries.map { audioDirectory.appendingPathComponent($0.audioFileName) }
        fileIOQueue.async {
            for audioURL in audioURLs {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }

        DispatchQueue.main.async {
            self.entries.removeAll()
            self.saveHistory()
            self.entriesDidChange.send()
        }
    }

    func applyRetentionPolicy() {
        DispatchQueue.main.async {
            let previousCount = self.entries.count
            self.enforceRetentionPolicy()
            guard self.entries.count != previousCount else { return }
            self.saveHistory()
            self.entriesDidChange.send()
        }
    }

    func getAudioData(for entry: HistoryEntry) -> Data? {
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        return try? Data(contentsOf: audioURL)
    }

    func audioFileSize(for entry: HistoryEntry) -> Int64? {
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    /// Get audio duration for a history entry
    func audioDuration(for entry: HistoryEntry) -> TimeInterval? {
        guard let size = audioFileSize(for: entry) else { return nil }
        return entry.audioDuration(fileSize: size)
    }

    // MARK: - Private Methods

    private func migrateRetentionSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationVersion = defaults.integer(forKey: Self.retentionSettingsMigrationVersionKey)
        guard migrationVersion < Self.retentionSettingsMigrationVersion else { return }

        if let rawNumber = defaults.object(forKey: Self.maxEntriesDefaultsKey) as? NSNumber {
            let value = rawNumber.intValue
            if value == Self.legacyDefaultMaxEntriesV0 || value == Self.legacyDefaultMaxEntriesV1 {
                defaults.set(Self.defaultMaxEntries, forKey: Self.maxEntriesDefaultsKey)
            }
        }

        defaults.set(Self.retentionSettingsMigrationVersion, forKey: Self.retentionSettingsMigrationVersionKey)
    }

    private func ensureDirectoriesExist() {
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: appSupportDirectory.path) {
            try? fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: audioDirectory.path) {
            try? fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        }
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            // Atomic: a crash or kill mid-write must not leave a truncated file behind.
            try data.write(to: historyFile, options: .atomic)
        } catch {
            print("[Hibiki] Failed to save history: \(error)")
        }
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFile.path) else { return }

        do {
            let data = try Data(contentsOf: historyFile)
            let decoded = try Self.decodeEntries(from: data)
            entries = decoded.entries
            if decoded.droppedCount > 0 {
                print("[Hibiki] Skipped \(decoded.droppedCount) unreadable history entries")
                preserveUnreadableHistoryFile(removingOriginal: false)
            }
        } catch {
            // The next save would overwrite the file with an empty history; keep it instead.
            print("[Hibiki] Failed to load history: \(error)")
            preserveUnreadableHistoryFile(removingOriginal: true)
        }
    }

    /// Decodes the history file entry by entry, so a single entry that no longer matches the
    /// schema (or is damaged) costs that entry instead of the whole history.
    static func decodeEntries(from data: Data) throws -> (entries: [HistoryEntry], droppedCount: Int) {
        struct Lossy: Decodable {
            let entry: HistoryEntry?

            init(from decoder: Decoder) throws {
                entry = try? HistoryEntry(from: decoder)
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Lossy].self, from: data)
        let entries = decoded.compactMap(\.entry)
        return (entries, decoded.count - entries.count)
    }

    private func preserveUnreadableHistoryFile(removingOriginal: Bool) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = appSupportDirectory.appendingPathComponent("history.unreadable-\(stamp).json")
        do {
            if removingOriginal {
                try FileManager.default.moveItem(at: historyFile, to: backup)
            } else {
                try FileManager.default.copyItem(at: historyFile, to: backup)
            }
            print("[Hibiki] Kept unreadable history as \(backup.lastPathComponent)")
        } catch {
            print("[Hibiki] Could not preserve unreadable history file: \(error)")
        }
    }

    private func enforceRetentionPolicy() {
        var removedEntries: [HistoryEntry] = []
        let calendar = Calendar.current

        let retentionDays = currentRetentionDays
        if let cutoffDate = calendar.date(
            byAdding: .day,
            value: -(retentionDays - 1),
            to: calendar.startOfDay(for: Date())
        ) {
            let staleEntries = entries.filter { $0.timestamp < cutoffDate }
            if !staleEntries.isEmpty {
                removedEntries.append(contentsOf: staleEntries)
                entries.removeAll { $0.timestamp < cutoffDate }
            }
        }

        // Enforce max entries
        let maxEntries = currentMaxEntries
        while entries.count > maxEntries {
            if let lastEntry = entries.last {
                removedEntries.append(lastEntry)
                entries.removeLast()
            }
        }

        // Enforce max disk space
        var totalSize = calculateTotalDiskUsage()
        let maxBytes = Int64(currentMaxDiskSpaceMB * 1024 * 1024)

        while totalSize > maxBytes && !entries.isEmpty {
            if let lastEntry = entries.last {
                removedEntries.append(lastEntry)
                entries.removeLast()
                totalSize = calculateTotalDiskUsage()
            }
        }

        if !removedEntries.isEmpty {
            let urlsToDelete = removedEntries.map { audioDirectory.appendingPathComponent($0.audioFileName) }
            fileIOQueue.async {
                for url in urlsToDelete {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private var currentRetentionDays: Int {
        clampedSetting(
            forKey: Self.retentionDaysDefaultsKey,
            defaultValue: Self.defaultRetentionDays,
            lowerBound: Self.minRetentionDays,
            upperBound: Self.maxRetentionDays
        )
    }

    private var currentMaxEntries: Int {
        clampedSetting(
            forKey: Self.maxEntriesDefaultsKey,
            defaultValue: Self.defaultMaxEntries,
            lowerBound: Self.minMaxEntries,
            upperBound: Self.maxMaxEntries
        )
    }

    private var currentMaxDiskSpaceMB: Double {
        clampedDoubleSetting(
            forKey: Self.maxDiskSpaceDefaultsKey,
            defaultValue: Self.defaultMaxDiskSpaceMB,
            lowerBound: Self.minMaxDiskSpaceMB,
            upperBound: Self.maxMaxDiskSpaceMB
        )
    }

    private func clampedSetting(
        forKey key: String,
        defaultValue: Int,
        lowerBound: Int,
        upperBound: Int
    ) -> Int {
        guard let rawNumber = UserDefaults.standard.object(forKey: key) as? NSNumber else {
            return defaultValue
        }

        let raw = rawNumber.intValue

        let clamped = Swift.min(Swift.max(raw, lowerBound), upperBound)
        if clamped != raw {
            UserDefaults.standard.set(clamped, forKey: key)
        }
        return clamped
    }

    private func clampedDoubleSetting(
        forKey key: String,
        defaultValue: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        guard let rawNumber = UserDefaults.standard.object(forKey: key) as? NSNumber else {
            return defaultValue
        }

        let raw = rawNumber.doubleValue
        let clamped = Swift.min(Swift.max(raw, lowerBound), upperBound)
        if clamped != raw {
            UserDefaults.standard.set(clamped, forKey: key)
        }
        return clamped
    }

    private func calculateTotalDiskUsage() -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default

        for entry in entries {
            let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
            if let attributes = try? fileManager.attributesOfItem(atPath: audioURL.path),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }

        return totalSize
    }

    var totalCost: Double {
        entries.reduce(0) { $0 + $1.cost }
    }

    var formattedTotalCost: String {
        String(format: "$%.6f", totalCost)
    }
}
