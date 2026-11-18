import XCTest
@testable import Hibiki

final class UsageLedgerTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hibiki-ledger-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("usage-ledger.json")
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func entry(on date: Date, text: String = "one two three", tokens: Int = 1_000) -> HistoryEntry {
        HistoryEntry(timestamp: date, text: text, voice: "coral", inputTokens: tokens, audioFileName: "a.pcm", ttsCost: 0.25)
    }

    private func makeLedger() -> UsageLedger {
        UsageLedger(fileURL: fileURL, calendar: calendar)
    }

    private func calculator(_ ledger: UsageLedger) -> UsageStatisticsCalculator {
        UsageStatisticsCalculator(totalsByDay: ledger.snapshot(), calendar: calendar)
    }

    func testRecordAccumulatesPerDay() {
        let ledger = makeLedger()
        ledger.record(entry: entry(on: date(2026, 11, 18, hour: 9)), audioByteCount: 48_000 * 60)
        ledger.record(entry: entry(on: date(2026, 11, 18, hour: 21)), audioByteCount: 48_000 * 30)
        ledger.record(entry: entry(on: date(2026, 11, 17)), audioByteCount: 0)

        let totals = ledger.snapshot()
        let day = calendar.startOfDay(for: date(2026, 11, 18))
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals[day]?.requestCount, 2)
        XCTAssertEqual(totals[day]?.wordCount, 6)
        XCTAssertEqual(totals[day]?.audioSeconds ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(totals[day]?.ttsCost ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(totals[day]?.cost ?? 0, 0.5, accuracy: 1e-9)
    }

    func testTotalsSurviveReload() {
        makeLedger().record(entry: entry(on: date(2026, 11, 18)), audioByteCount: 48_000)

        let reloaded = makeLedger()
        XCTAssertTrue(reloaded.existsOnDisk)
        XCTAssertEqual(reloaded.snapshot().values.first?.requestCount, 1)
    }

    func testSeedsFromHistoryOnlyOnce() {
        let history = [entry(on: date(2026, 11, 10)), entry(on: date(2026, 11, 11))]

        let first = makeLedger()
        first.seedIfNeeded(from: history) { _ in 48_000 }
        XCTAssertEqual(calculator(first).calculateAllTimeSummary().requestCount, 2)

        // Next launch: the same entries are still in history and must not be counted again.
        let second = makeLedger()
        second.seedIfNeeded(from: history) { _ in 48_000 }
        XCTAssertEqual(calculator(second).calculateAllTimeSummary().requestCount, 2)
    }

    /// Regression: statistics were computed from history, which retention prunes to 7 days by
    /// default, so "This Month" and "All Time" dropped everything older than a week.
    func testMonthAndAllTimeIncludeUsageOlderThanHistoryRetention() {
        let ledger = makeLedger()
        let today = date(2026, 11, 28)
        ledger.record(entry: entry(on: today), audioByteCount: 48_000 * 60)
        ledger.record(entry: entry(on: date(2026, 11, 3)), audioByteCount: 48_000 * 60)   // 25 days ago
        ledger.record(entry: entry(on: date(2026, 9, 15)), audioByteCount: 48_000 * 60)   // earlier month
        ledger.record(entry: entry(on: date(2025, 11, 20)), audioByteCount: 48_000 * 60)  // same month last year

        let stats = calculator(ledger)
        XCTAssertEqual(stats.calculateTodaySummary(referenceDate: today).requestCount, 1)
        XCTAssertEqual(stats.calculateThisMonthSummary(referenceDate: today).requestCount, 2)
        XCTAssertEqual(stats.calculateAllTimeSummary().requestCount, 4)
        XCTAssertEqual(stats.calculateAllTimeSummary().audioMinutes, 4, accuracy: 0.001)
    }

    func testDailyUsageWindowIsZeroFilledAndOrdered() {
        let ledger = makeLedger()
        let today = date(2026, 11, 18)
        ledger.record(entry: entry(on: today), audioByteCount: 0)
        ledger.record(entry: entry(on: date(2026, 11, 16)), audioByteCount: 0)
        ledger.record(entry: entry(on: date(2026, 11, 1)), audioByteCount: 0)  // outside the window

        let week = calculator(ledger).dailyUsage(days: 7, referenceDate: today)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map(\.requestCount), [0, 0, 0, 0, 1, 0, 1])
        XCTAssertEqual(week.last?.date, calendar.startOfDay(for: today))

        let trimmed = calculator(ledger).recentWeekUsageStartingFromFirstActiveDay(referenceDate: today)
        XCTAssertEqual(trimmed.map(\.requestCount), [1, 0, 1])
    }

    func testCorruptLedgerIsSetAsideAndReseeded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let ledger = makeLedger()
        XCTAssertFalse(ledger.existsOnDisk)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("corrupt").path))

        ledger.seedIfNeeded(from: [entry(on: date(2026, 11, 10))]) { _ in 0 }
        XCTAssertEqual(calculator(ledger).calculateAllTimeSummary().requestCount, 1)
    }
}
