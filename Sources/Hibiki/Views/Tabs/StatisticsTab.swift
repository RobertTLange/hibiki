import SwiftUI
import Charts
import Combine

struct StatisticsTab: View {
    @State private var dailyUsage: [DailyUsage] = []
    @State private var costDataPoints: [CostDataPoint] = []
    @State private var todaySummary: PeriodSummary = .zero
    @State private var monthSummary: PeriodSummary = .zero
    @State private var allTimeSummary: PeriodSummary = .zero
    @State private var isLoading = true
    @State private var isVisible = false  // Track visibility to control chart rendering
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Cards Row
                HStack(spacing: 16) {
                    SummaryCard(
                        title: "Today",
                        summary: todaySummary,
                        isLoading: isLoading
                    )
                    SummaryCard(
                        title: "This Month",
                        summary: monthSummary,
                        isLoading: isLoading
                    )
                    SummaryCard(
                        title: "All Time",
                        summary: allTimeSummary,
                        isLoading: isLoading
                    )
                }

                // Only render charts when view is visible to prevent freeze on tab switch
                if isVisible {
                    // Cost Over Time Chart - Multi-line with Total, TTS, and LLM
                    GroupBox("Cost Over Time") {
                        if isLoading {
                            loadingChartView
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.cost == 0 }) {
                            emptyChartView
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Chart(costDataPoints) { point in
                                    LineMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value("Cost", point.cost)
                                    )
                                    .foregroundStyle(by: .value("Category", point.category.rawValue))
                                    .interpolationMethod(.catmullRom)
                                }
                                .frame(height: 180)
                                .chartForegroundStyleScale([
                                    "Total": Color.blue,
                                    "TTS": Color.purple,
                                    "LLM": Color.orange,
                                    "Translation": Color(red: 0.3, green: 0.55, blue: 0.85)
                                ])
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                        AxisGridLine()
                                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks { value in
                                        AxisGridLine()
                                        AxisValueLabel {
                                            if let cost = value.as(Double.self) {
                                                Text(String(format: "$%.4f", cost))
                                            }
                                        }
                                    }
                                }
                                .chartLegend(position: .bottom, alignment: .center)
                            }
                        }
                    }

                    // Words Per Day Chart
                    GroupBox("Words Per Day") {
                        if isLoading {
                            loadingChartView
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.wordCount == 0 }) {
                            emptyChartView
                        } else {
                            Chart(dailyUsage) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Words", day.wordCount)
                                )
                                .foregroundStyle(.green.gradient)
                            }
                            .frame(height: 150)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                        }
                    }

                    // Audio Minutes Chart
                    GroupBox("Audio Minutes Per Day") {
                        if isLoading {
                            loadingChartView
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.audioMinutes == 0 }) {
                            emptyChartView
                        } else {
                            Chart(dailyUsage) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Minutes", day.audioMinutes)
                                )
                                .foregroundStyle(.purple.gradient)
                            }
                            .frame(height: 150)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine()
                                    AxisValueLabel {
                                        if let mins = value.as(Double.self) {
                                            Text(String(format: "%.1f", mins))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Requests Per Day Chart
                    GroupBox("Requests Per Day") {
                        if isLoading {
                            loadingChartView
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.requestCount == 0 }) {
                            emptyChartView
                        } else {
                            Chart(dailyUsage) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Requests", day.requestCount)
                                )
                                .foregroundStyle(.orange.gradient)
                            }
                            .frame(height: 150)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                        }
                    }
                } else {
                    // Placeholder while charts are hidden during tab transition
                    GroupBox("Cost Over Time") { loadingChartView }
                    GroupBox("Words Per Day") { loadingChartView }
                    GroupBox("Audio Minutes Per Day") { loadingChartView }
                    GroupBox("Requests Per Day") { loadingChartView }
                }
            }
            .padding()
        }
        .onAppear {
            loadStatisticsSync()
            // Delay setting visible to allow tab animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
            }
            // Subscribe to history changes
            HistoryManager.shared.entriesDidChange
                .receive(on: DispatchQueue.main)
                .sink { [self] _ in
                    reloadStatistics()
                }
                .store(in: &cancellables)
        }
        .onDisappear {
            // Hide charts immediately when leaving to prevent freeze
            isVisible = false
        }
    }
    
    /// Reload statistics when history changes
    private func reloadStatistics() {
        let historyManager = HistoryManager.shared
        let entriesSnapshot = historyManager.entries
        let audioDir = historyManager.audioDirectory

        let calculator = UsageStatisticsCalculator(entries: entriesSnapshot, audioDirectory: audioDir)

        self.dailyUsage = calculator.dailyUsage(days: 30)
        self.costDataPoints = buildCostDataPoints(from: dailyUsage)
        self.todaySummary = calculator.calculateTodaySummary()
        self.monthSummary = calculator.calculateThisMonthSummary()
        self.allTimeSummary = calculator.calculateAllTimeSummary()
    }
    
    /// Convert daily usage to cost data points for multi-line chart
    private func buildCostDataPoints(from usage: [DailyUsage]) -> [CostDataPoint] {
        var points: [CostDataPoint] = []
        for day in usage {
            points.append(CostDataPoint(date: day.date, cost: day.cost, category: .total))
            points.append(CostDataPoint(date: day.date, cost: day.ttsCost, category: .tts))
            points.append(CostDataPoint(date: day.date, cost: day.llmCost, category: .llm))
            points.append(CostDataPoint(date: day.date, cost: day.translationCost, category: .translation))
        }
        return points
    }

    private var loadingChartView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }

    private var emptyChartView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No data yet")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }

    /// Load statistics synchronously on the main thread.
    /// The calculations are fast enough that async is not needed,
    /// and using async/detached tasks was causing deadlocks when switching tabs.
    private func loadStatisticsSync() {
        // Skip if already loaded to prevent repeated calculations on tab switches
        guard isLoading else { return }
        
        let historyManager = HistoryManager.shared
        let entriesSnapshot = historyManager.entries
        let audioDir = historyManager.audioDirectory

        let calculator = UsageStatisticsCalculator(entries: entriesSnapshot, audioDirectory: audioDir)

        // These calculations are fast (just iterating over history entries)
        // Running synchronously avoids all the async/threading complexity
        self.dailyUsage = calculator.dailyUsage(days: 30)
        self.costDataPoints = buildCostDataPoints(from: dailyUsage)
        self.todaySummary = calculator.calculateTodaySummary()
        self.monthSummary = calculator.calculateThisMonthSummary()
        self.allTimeSummary = calculator.calculateAllTimeSummary()
        self.isLoading = false
    }
}

struct SummaryCard: View {
    let title: String
    let summary: PeriodSummary
    var isLoading: Bool = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                if isLoading {
                    VStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(.blue)
                            Text(String(format: "$%.4f", summary.cost))
                            Spacer()
                        }
                        
                        HStack {
                            Image(systemName: "speaker.wave.2")
                                .foregroundColor(.purple)
                            Text(String(format: "TTS: $%.4f", summary.ttsCost))
                            Spacer()
                        }
                        
                        HStack {
                            Image(systemName: "brain")
                                .foregroundColor(.orange)
                            Text(String(format: "LLM: $%.4f", summary.llmCost))
                            Spacer()
                        }

                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(Color(red: 0.3, green: 0.55, blue: 0.85))
                            Text(String(format: "Trans: $%.4f", summary.translationCost))
                            Spacer()
                        }

                        HStack {
                            Image(systemName: "text.alignleft")
                                .foregroundColor(.teal)
                            Text("\(summary.wordCount) words")
                            Spacer()
                        }

                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.cyan)
                            Text(String(format: "%.1f min", summary.audioMinutes))
                            Spacer()
                        }

                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.gray)
                            Text("\(summary.requestCount) requests")
                            Spacer()
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
