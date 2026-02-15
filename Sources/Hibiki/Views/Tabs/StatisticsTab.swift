import SwiftUI
import Charts
import Combine

struct StatisticsTab: View {
    @State private var dailyUsage: [DailyUsage] = []
    @State private var costDataPoints: [CostDataPoint] = []
    @State private var todaySummary: PeriodSummary = .zero
    @State private var monthSummary: PeriodSummary = .zero
    @State private var allTimeSummary: PeriodSummary = .zero
    @State private var hoveredDate: Date?
    @State private var hoveredPanel: StatisticsChartPanel?
    @State private var hoveredPlotLocation: CGPoint?
    @State private var isLoading = true
    @State private var isVisible = false  // Track visibility to control chart rendering
    @State private var chartsReady = false  // Only true after data is validated and delay passed
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

                // Only render charts when data is ready and validated to prevent Charts framework crash
                if chartsReady {
                    // Cost Over Time Chart - Multi-line with Total, TTS, and LLM
                    GroupBox("Cost Over Time") {
                        if isLoading {
                            StatisticsLoadingChartView()
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.cost == 0 }) {
                            StatisticsEmptyChartView()
                        } else {
                            Chart(costDataPoints) { point in
                                LineMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Cost", point.cost)
                                )
                                .foregroundStyle(by: .value("Category", point.category.rawValue))
                                .interpolationMethod(.catmullRom)

                                if let hoveredDay = hoveredUsageDay(for: .cost) {
                                    RuleMark(x: .value("Hovered Date", hoveredDay.date, unit: .day))
                                        .foregroundStyle(Color.secondary.opacity(0.4))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                                    PointMark(
                                        x: .value("Date", hoveredDay.date, unit: .day),
                                        y: .value("Cost", hoveredDay.cost)
                                    )
                                    .symbolSize(50)
                                    .foregroundStyle(Color.blue)

                                    PointMark(
                                        x: .value("Date", hoveredDay.date, unit: .day),
                                        y: .value("Cost", hoveredDay.ttsCost)
                                    )
                                    .symbolSize(45)
                                    .foregroundStyle(Color.purple)

                                    PointMark(
                                        x: .value("Date", hoveredDay.date, unit: .day),
                                        y: .value("Cost", hoveredDay.llmCost)
                                    )
                                    .symbolSize(45)
                                    .foregroundStyle(Color.orange)

                                    PointMark(
                                        x: .value("Date", hoveredDay.date, unit: .day),
                                        y: .value("Cost", hoveredDay.translationCost)
                                    )
                                    .symbolSize(45)
                                    .foregroundStyle(Color(red: 0.3, green: 0.55, blue: 0.85))
                                }
                            }
                            .frame(height: 180)
                            .chartForegroundStyleScale([
                                "Total": Color.blue,
                                "TTS": Color.purple,
                                "LLM": Color.orange,
                                "Translation": Color(red: 0.3, green: 0.55, blue: 0.85)
                            ])
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
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
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    chartHoverOverlay(panel: .cost, focus: .cost, proxy: proxy, geometry: geometry)
                                }
                            }
                        }
                    }

                    // Words Per Day Chart
                    GroupBox("Words Per Day") {
                        if isLoading {
                            StatisticsLoadingChartView()
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.wordCount == 0 }) {
                            StatisticsEmptyChartView()
                        } else {
                            Chart(dailyUsage) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Words", day.wordCount)
                                )
                                .foregroundStyle(.green.gradient)

                                if let hoveredDay = hoveredUsageDay(for: .words) {
                                    RuleMark(x: .value("Hovered Date", hoveredDay.date, unit: .day))
                                        .foregroundStyle(Color.secondary.opacity(0.4))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
                            }
                            .frame(height: 150)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    chartHoverOverlay(panel: .words, focus: .words, proxy: proxy, geometry: geometry)
                                }
                            }
                        }
                    }

                    // Audio Minutes Chart
                    GroupBox("Audio Minutes Per Day") {
                        if isLoading {
                            StatisticsLoadingChartView()
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.audioMinutes == 0 }) {
                            StatisticsEmptyChartView()
                        } else {
                            Chart(dailyUsage) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Minutes", day.audioMinutes)
                                )
                                .foregroundStyle(.purple.gradient)

                                if let hoveredDay = hoveredUsageDay(for: .audio) {
                                    RuleMark(x: .value("Hovered Date", hoveredDay.date, unit: .day))
                                        .foregroundStyle(Color.secondary.opacity(0.4))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
                            }
                            .frame(height: 150)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
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
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    chartHoverOverlay(panel: .audio, focus: .audio, proxy: proxy, geometry: geometry)
                                }
                            }
                        }
                    }

                    // Requests Per Day Chart
                    GroupBox("Requests Per Day") {
                        if isLoading {
                            StatisticsLoadingChartView()
                        } else if dailyUsage.isEmpty || dailyUsage.allSatisfy({ $0.requestCount == 0 }) {
                            StatisticsEmptyChartView()
                        } else {
                            Chart(dailyUsage) { day in
                                BarMark(
                                    x: .value("Date", day.date, unit: .day),
                                    y: .value("Requests", day.requestCount)
                                )
                                .foregroundStyle(.orange.gradient)

                                if let hoveredDay = hoveredUsageDay(for: .requests) {
                                    RuleMark(x: .value("Hovered Date", hoveredDay.date, unit: .day))
                                        .foregroundStyle(Color.secondary.opacity(0.4))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
                            }
                            .frame(height: 150)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                }
                            }
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    chartHoverOverlay(panel: .requests, focus: .requests, proxy: proxy, geometry: geometry)
                                }
                            }
                        }
                    }
                } else {
                    // Placeholder while charts are hidden during tab transition
                    GroupBox("Cost Over Time") { StatisticsLoadingChartView() }
                    GroupBox("Words Per Day") { StatisticsLoadingChartView() }
                    GroupBox("Audio Minutes Per Day") { StatisticsLoadingChartView() }
                    GroupBox("Requests Per Day") { StatisticsLoadingChartView() }
                }
            }
            .padding()
        }
        .onAppear {
            // Reload statistics (will update charts since not visible yet)
            loadStatisticsSync()
            // Delay setting visible to allow tab animation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
            }
            // Longer delay before rendering charts to avoid Charts framework crash
            // The Charts framework can crash during initial rendering if data arrives too quickly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Only enable charts if data is valid
                if validateChartData() {
                    chartsReady = true
                }
            }
            // Subscribe to history changes
            HistoryManager.shared.entriesDidChange
                .receive(on: DispatchQueue.main)
                .sink { [self] _ in
                    reloadStatistics()
                }
                .store(in: &cancellables)
        }
        .onChange(of: isVisible) { _, newValue in
            // Reload chart data when becoming visible to catch any missed updates
            if newValue {
                // Disable charts while updating data
                chartsReady = false

                let historyManager = HistoryManager.shared
                let entriesSnapshot = historyManager.entries
                let audioDir = historyManager.audioDirectory
                let calculator = UsageStatisticsCalculator(entries: entriesSnapshot, audioDirectory: audioDir)
                loadRecentWeekUsage(from: calculator)

                // Re-enable charts after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if validateChartData() {
                        chartsReady = true
                    }
                }
            }
        }
        .onDisappear {
            // Hide charts immediately when leaving to prevent freeze
            chartsReady = false
            isVisible = false
            hoveredDate = nil
            hoveredPanel = nil
            hoveredPlotLocation = nil
        }
    }
    
    /// Reload statistics when history changes
    private func reloadStatistics() {
        // Don't update chart data while charts are rendering to avoid Charts framework crash
        // The chart will be updated when the tab becomes visible again
        guard !chartsReady else {
            // Just update the summary cards which don't cause crashes
            let historyManager = HistoryManager.shared
            let entriesSnapshot = historyManager.entries
            let audioDir = historyManager.audioDirectory
            let calculator = UsageStatisticsCalculator(entries: entriesSnapshot, audioDirectory: audioDir)
            self.todaySummary = calculator.calculateTodaySummary()
            self.monthSummary = calculator.calculateThisMonthSummary()
            self.allTimeSummary = calculator.calculateAllTimeSummary()
            return
        }

        let historyManager = HistoryManager.shared
        let entriesSnapshot = historyManager.entries
        let audioDir = historyManager.audioDirectory

        let calculator = UsageStatisticsCalculator(entries: entriesSnapshot, audioDirectory: audioDir)

        loadRecentWeekUsage(from: calculator)
        self.todaySummary = calculator.calculateTodaySummary()
        self.monthSummary = calculator.calculateThisMonthSummary()
        self.allTimeSummary = calculator.calculateAllTimeSummary()
    }

    /// Validate chart data to ensure it won't crash the Charts framework
    private func validateChartData() -> Bool {
        // Check for empty data (charts handle this, but be safe)
        guard !dailyUsage.isEmpty else { return true }

        // Check for NaN or infinity values in cost data
        for point in costDataPoints {
            if point.cost.isNaN || point.cost.isInfinite {
                print("[Hibiki] ⚠️ Invalid cost data point detected, skipping charts")
                return false
            }
        }

        // Check for NaN or infinity in daily usage
        for day in dailyUsage {
            if day.cost.isNaN || day.cost.isInfinite ||
               day.audioMinutes.isNaN || day.audioMinutes.isInfinite {
                print("[Hibiki] ⚠️ Invalid daily usage data detected, skipping charts")
                return false
            }
        }

        return true
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

    private func hoveredUsageDay(for panel: StatisticsChartPanel) -> DailyUsage? {
        guard hoveredPanel == panel, !dailyUsage.isEmpty, let hoveredDate else { return nil }
        let normalizedDate = Calendar.current.startOfDay(for: hoveredDate)
        return dailyUsage.min {
            abs($0.date.timeIntervalSince(normalizedDate)) < abs($1.date.timeIntervalSince(normalizedDate))
        }
    }

    @ViewBuilder
    private func chartHoverOverlay(
        panel: StatisticsChartPanel,
        focus: HoverTooltipFocus,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    handleHover(phase, panel: panel, proxy: proxy, geometry: geometry)
                }

            if let plotFrame = proxy.plotFrame,
               let hoveredDay = hoveredUsageDay(for: panel),
               let hoveredPlotLocation {
                let plotArea = geometry[plotFrame]
                let tooltipWidth: CGFloat = 230
                let tooltipHeight = focus.tooltipHeightEstimate
                let padding: CGFloat = 8
                let tooltipX = min(max(hoveredPlotLocation.x + 12, padding), plotArea.width - tooltipWidth - padding)
                let tooltipY = min(max(hoveredPlotLocation.y - (tooltipHeight / 2), padding), plotArea.height - tooltipHeight - padding)

                DailyUsageHoverTooltip(day: hoveredDay, focus: focus)
                    .frame(width: tooltipWidth, alignment: .leading)
                    .offset(x: plotArea.origin.x + tooltipX, y: plotArea.origin.y + tooltipY)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handleHover(
        _ phase: HoverPhase,
        panel: StatisticsChartPanel,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        switch phase {
        case .active(let location):
            guard let plotFrame = proxy.plotFrame else {
                hoveredDate = nil
                hoveredPanel = nil
                hoveredPlotLocation = nil
                return
            }
            let plotArea = geometry[plotFrame]
            guard plotArea.contains(location) else {
                if hoveredPanel == panel {
                    hoveredDate = nil
                    hoveredPanel = nil
                    hoveredPlotLocation = nil
                }
                return
            }

            let xPosition = location.x - plotArea.origin.x
            guard let date: Date = proxy.value(atX: xPosition) else {
                if hoveredPanel == panel {
                    hoveredDate = nil
                    hoveredPanel = nil
                    hoveredPlotLocation = nil
                }
                return
            }
            hoveredDate = Calendar.current.startOfDay(for: date)
            hoveredPanel = panel
            hoveredPlotLocation = CGPoint(x: xPosition, y: location.y - plotArea.origin.y)
        case .ended:
            if hoveredPanel == panel {
                hoveredDate = nil
                hoveredPanel = nil
                hoveredPlotLocation = nil
            }
        }
    }

    private func loadRecentWeekUsage(from calculator: UsageStatisticsCalculator) {
        self.dailyUsage = calculator.recentWeekUsageStartingFromFirstActiveDay()
        self.costDataPoints = buildCostDataPoints(from: dailyUsage)
        self.hoveredDate = nil
        self.hoveredPanel = nil
        self.hoveredPlotLocation = nil
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
        loadRecentWeekUsage(from: calculator)
        self.todaySummary = calculator.calculateTodaySummary()
        self.monthSummary = calculator.calculateThisMonthSummary()
        self.allTimeSummary = calculator.calculateAllTimeSummary()
        self.isLoading = false
    }
}
