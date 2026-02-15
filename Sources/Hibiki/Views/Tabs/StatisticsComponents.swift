import SwiftUI

enum StatisticsChartPanel {
    case cost
    case words
    case audio
    case requests
}

enum HoverTooltipFocus {
    case cost
    case words
    case audio
    case requests

    func primaryText(for day: DailyUsage) -> String {
        switch self {
        case .cost:
            return String(format: "Total $%.4f", day.cost)
        case .words:
            return "\(day.wordCount) words"
        case .audio:
            return String(format: "%.1f audio min", day.audioMinutes)
        case .requests:
            return "\(day.requestCount) requests"
        }
    }

    var tooltipHeightEstimate: CGFloat {
        switch self {
        case .cost:
            return 98
        case .words, .audio, .requests:
            return 78
        }
    }
}

struct DailyUsageHoverTooltip: View {
    let day: DailyUsage
    let focus: HoverTooltipFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.caption2)
                .fontWeight(.semibold)

            Text(focus.primaryText(for: day))
                .font(.caption)
                .fontWeight(.semibold)

            Text(String(format: "Cost $%.4f · Words %d · %.1f min · %d req", day.cost, day.wordCount, day.audioMinutes, day.requestCount))
                .font(.caption2)

            if focus == .cost {
                Text(String(format: "TTS $%.4f · LLM $%.4f · Trans $%.4f", day.ttsCost, day.llmCost, day.translationCost))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct StatisticsLoadingChartView: View {
    var body: some View {
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
}

struct StatisticsEmptyChartView: View {
    var body: some View {
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
