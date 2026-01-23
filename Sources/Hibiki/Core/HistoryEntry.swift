import Foundation

struct HistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let text: String
    let voice: String
    let inputTokens: Int
    let cost: Double
    let audioFileName: String

    init(id: UUID = UUID(), timestamp: Date = Date(), text: String, voice: String, inputTokens: Int, audioFileName: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.voice = voice
        self.inputTokens = inputTokens
        self.cost = TTSPricing.calculateCost(inputTokens: inputTokens)
        self.audioFileName = audioFileName
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    var formattedCost: String {
        String(format: "$%.6f", cost)
    }

    var truncatedText: String {
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

enum TTSPricing {
    // gpt-4o-mini-tts pricing: $0.60 per 1M input tokens
    static let costPerMillionTokens: Double = 0.60

    static func calculateCost(inputTokens: Int) -> Double {
        return Double(inputTokens) / 1_000_000.0 * costPerMillionTokens
    }
}
