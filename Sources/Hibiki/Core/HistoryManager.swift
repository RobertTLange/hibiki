import Foundation

@Observable
final class HistoryManager {
    static let shared = HistoryManager()

    private(set) var entries: [HistoryEntry] = []

    private let maxEntries = 100
    private let maxDiskSpaceMB: Double = 500

    private var appSupportDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Hibiki", isDirectory: true)
    }

    private var historyFile: URL {
        appSupportDirectory.appendingPathComponent("history.json")
    }

    private var audioDirectory: URL {
        appSupportDirectory.appendingPathComponent("audio", isDirectory: true)
    }

    private init() {
        ensureDirectoriesExist()
        loadHistory()
    }

    // MARK: - Public API

    @discardableResult
    func addEntry(text: String, voice: String, inputTokens: Int, audioData: Data) -> HistoryEntry {
        let audioFileName = "\(UUID().uuidString).pcm"
        let audioURL = audioDirectory.appendingPathComponent(audioFileName)

        // Save audio file
        do {
            try audioData.write(to: audioURL)
        } catch {
            print("[Hibiki] Failed to save audio file: \(error)")
        }

        let entry = HistoryEntry(
            text: text,
            voice: voice,
            inputTokens: inputTokens,
            audioFileName: audioFileName
        )

        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            self.saveHistory()
            self.enforceRetentionPolicy()
        }

        return entry
    }

    func deleteEntry(_ entry: HistoryEntry) {
        // Delete audio file
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        try? FileManager.default.removeItem(at: audioURL)

        DispatchQueue.main.async {
            self.entries.removeAll { $0.id == entry.id }
            self.saveHistory()
        }
    }

    func clearAllHistory() {
        // Delete all audio files
        for entry in entries {
            let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
            try? FileManager.default.removeItem(at: audioURL)
        }

        DispatchQueue.main.async {
            self.entries.removeAll()
            self.saveHistory()
        }
    }

    func getAudioData(for entry: HistoryEntry) -> Data? {
        let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
        return try? Data(contentsOf: audioURL)
    }

    // MARK: - Private Methods

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
            try data.write(to: historyFile)
        } catch {
            print("[Hibiki] Failed to save history: \(error)")
        }
    }

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyFile.path) else { return }

        do {
            let data = try Data(contentsOf: historyFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            print("[Hibiki] Failed to load history: \(error)")
        }
    }

    private func enforceRetentionPolicy() {
        // Enforce max entries
        while entries.count > maxEntries {
            if let lastEntry = entries.last {
                deleteEntry(lastEntry)
            }
        }

        // Enforce max disk space
        var totalSize = calculateTotalDiskUsage()
        let maxBytes = Int64(maxDiskSpaceMB * 1024 * 1024)

        while totalSize > maxBytes && !entries.isEmpty {
            if let lastEntry = entries.last {
                deleteEntry(lastEntry)
                totalSize = calculateTotalDiskUsage()
            }
        }
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
