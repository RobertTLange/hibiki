import Foundation

struct DailyUsage: Identifiable, Sendable {
    let id: Date
    let date: Date
    let cost: Double
    let ttsCost: Double
    let llmCost: Double
    let translationCost: Double
    let wordCount: Int
    let audioMinutes: Double
    let requestCount: Int

    static func empty(for date: Date) -> DailyUsage {
        DailyUsage(id: date, date: date, cost: 0, ttsCost: 0, llmCost: 0, translationCost: 0, wordCount: 0, audioMinutes: 0, requestCount: 0)
    }
}

/// For multi-line chart data
struct CostDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cost: Double
    let category: CostCategory
}

enum CostCategory: String, CaseIterable {
    case total = "Total"
    case tts = "TTS"
    case llm = "LLM"
    case translation = "Translation"

    var color: String {
        switch self {
        case .total: return "blue"
        case .tts: return "purple"
        case .llm: return "orange"
        case .translation: return "skyblue"
        }
    }
}

struct PeriodSummary: Sendable {
    let cost: Double
    let ttsCost: Double
    let llmCost: Double
    let translationCost: Double
    let wordCount: Int
    let audioMinutes: Double
    let requestCount: Int

    static let zero = PeriodSummary(cost: 0, ttsCost: 0, llmCost: 0, translationCost: 0, wordCount: 0, audioMinutes: 0, requestCount: 0)
}

/// Thread-safe calculator that works with pre-fetched data
/// IMPORTANT: All data must be captured on the main thread before passing to this calculator
final class UsageStatisticsCalculator: Sendable {
    private let entries: [HistoryEntry]
    private let audioDirectory: URL

    /// Initialize with a snapshot of entries and the audio directory path
    /// Call this initializer on the main thread to capture data safely
    init(entries: [HistoryEntry], audioDirectory: URL) {
        self.entries = entries
        self.audioDirectory = audioDirectory
    }

    /// Calculate daily usage for the last N days
    func dailyUsage(days: Int = 30, referenceDate: Date = Date()) -> [DailyUsage] {
        guard days > 0 else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)

        // Group entries by day
        let entriesByDay = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        // Build array for last N days (including days with no usage)
        var result: [DailyUsage] = []
        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            if let dayEntries = entriesByDay[date] {
                let cost = dayEntries.reduce(0) { $0 + $1.cost }
                let ttsCost = dayEntries.reduce(0) { $0 + $1.ttsCost }
                let llmCost = dayEntries.reduce(0) { $0 + ($1.llmCost ?? 0) }
                let translationCost = dayEntries.reduce(0) { $0 + ($1.translationCost ?? 0) }
                let words = dayEntries.reduce(0) { $0 + $1.wordCount }
                let minutes = calculateAudioMinutes(for: dayEntries)

                result.append(DailyUsage(
                    id: date,
                    date: date,
                    cost: cost,
                    ttsCost: ttsCost,
                    llmCost: llmCost,
                    translationCost: translationCost,
                    wordCount: words,
                    audioMinutes: minutes,
                    requestCount: dayEntries.count
                ))
            } else {
                result.append(.empty(for: date))
            }
        }

        return result
    }

    /// Recent week window, trimmed so it starts at the first active day in that week.
    /// If there is no activity in the last 7 days, returns the full 7-day zero-filled window.
    func recentWeekUsageStartingFromFirstActiveDay(referenceDate: Date = Date()) -> [DailyUsage] {
        let usage = dailyUsage(days: 7, referenceDate: referenceDate)
        guard let firstActiveIndex = usage.firstIndex(where: { $0.requestCount > 0 }) else {
            return usage
        }
        return Array(usage[firstActiveIndex...])
    }

    /// Summary for today
    func calculateTodaySummary() -> PeriodSummary {
        let today = Calendar.current.startOfDay(for: Date())
        let todayEntries = entries.filter {
            Calendar.current.startOfDay(for: $0.timestamp) == today
        }
        return summarize(todayEntries)
    }

    /// Summary for this month
    func calculateThisMonthSummary() -> PeriodSummary {
        let now = Date()
        let monthEntries = entries.filter {
            Calendar.current.isDate($0.timestamp, equalTo: now, toGranularity: .month)
        }
        return summarize(monthEntries)
    }

    /// Summary for all time
    func calculateAllTimeSummary() -> PeriodSummary {
        summarize(entries)
    }

    private func summarize(_ entries: [HistoryEntry]) -> PeriodSummary {
        PeriodSummary(
            cost: entries.reduce(0) { $0 + $1.cost },
            ttsCost: entries.reduce(0) { $0 + $1.ttsCost },
            llmCost: entries.reduce(0) { $0 + ($1.llmCost ?? 0) },
            translationCost: entries.reduce(0) { $0 + ($1.translationCost ?? 0) },
            wordCount: entries.reduce(0) { $0 + $1.wordCount },
            audioMinutes: calculateAudioMinutes(for: entries),
            requestCount: entries.count
        )
    }

    private func calculateAudioMinutes(for entries: [HistoryEntry]) -> Double {
        var total: Double = 0
        for entry in entries {
            let audioURL = audioDirectory.appendingPathComponent(entry.audioFileName)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
               let size = attributes[.size] as? Int64 {
                // PCM 24kHz 16-bit mono = 48000 bytes/second
                total += Double(size) / 48000.0 / 60.0
            }
        }
        return total
    }
}
