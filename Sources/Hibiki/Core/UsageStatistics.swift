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

/// Usage statistics over per-day totals from `UsageLedger`.
///
/// The totals come from the ledger rather than from history entries because history is
/// pruned by the retention policy; see `UsageLedger`.
struct UsageStatisticsCalculator: Sendable {
    private let totalsByDay: [Date: DayUsageTotals]
    private let calendar: Calendar

    /// - Parameter totalsByDay: totals keyed by the start of each local day.
    init(totalsByDay: [Date: DayUsageTotals], calendar: Calendar = .current) {
        self.totalsByDay = totalsByDay
        self.calendar = calendar
    }

    /// Calculate daily usage for the last N days
    func dailyUsage(days: Int = 30, referenceDate: Date = Date()) -> [DailyUsage] {
        guard days > 0 else { return [] }

        let today = calendar.startOfDay(for: referenceDate)

        // Build array for last N days (including days with no usage)
        var result: [DailyUsage] = []
        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            guard let totals = totalsByDay[date] else {
                result.append(.empty(for: date))
                continue
            }

            result.append(DailyUsage(
                id: date,
                date: date,
                cost: totals.cost,
                ttsCost: totals.ttsCost,
                llmCost: totals.llmCost,
                translationCost: totals.translationCost,
                wordCount: totals.wordCount,
                audioMinutes: totals.audioSeconds / 60.0,
                requestCount: totals.requestCount
            ))
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
    func calculateTodaySummary(referenceDate: Date = Date()) -> PeriodSummary {
        summarize { calendar.isDate($0, inSameDayAs: referenceDate) }
    }

    /// Summary for this month
    func calculateThisMonthSummary(referenceDate: Date = Date()) -> PeriodSummary {
        summarize { calendar.isDate($0, equalTo: referenceDate, toGranularity: .month) }
    }

    /// Summary for all time
    func calculateAllTimeSummary() -> PeriodSummary {
        summarize { _ in true }
    }

    private func summarize(where includesDay: (Date) -> Bool) -> PeriodSummary {
        var total = DayUsageTotals.zero
        for (day, totals) in totalsByDay where includesDay(day) {
            total.add(totals)
        }
        return PeriodSummary(
            cost: total.cost,
            ttsCost: total.ttsCost,
            llmCost: total.llmCost,
            translationCost: total.translationCost,
            wordCount: total.wordCount,
            audioMinutes: total.audioSeconds / 60.0,
            requestCount: total.requestCount
        )
    }
}
