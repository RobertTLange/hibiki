import Foundation

struct HistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let text: String
    let voice: String
    let inputTokens: Int
    let audioFileName: String

    // Separate cost tracking
    let ttsCost: Double
    let llmCost: Double?
    let translationCost: Double?
    let cost: Double  // Total cost (ttsCost + llmCost + translationCost)

    // Summarization metadata (optional - nil if direct TTS)
    let wasSummarized: Bool
    let summarizedText: String?
    let llmInputTokens: Int?
    let llmOutputTokens: Int?
    let llmModel: String?

    // Translation metadata (optional - nil if no translation)
    let wasTranslated: Bool
    let translatedText: String?
    let translationInputTokens: Int?
    let translationOutputTokens: Int?
    let translationModel: String?
    let targetLanguage: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        text: String,
        voice: String,
        inputTokens: Int,
        audioFileName: String,
        summarizedText: String? = nil,
        llmInputTokens: Int? = nil,
        llmOutputTokens: Int? = nil,
        llmModel: String? = nil,
        translatedText: String? = nil,
        translationInputTokens: Int? = nil,
        translationOutputTokens: Int? = nil,
        translationModel: String? = nil,
        targetLanguage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.voice = voice
        self.inputTokens = inputTokens
        self.audioFileName = audioFileName

        // Summarization fields
        self.wasSummarized = summarizedText != nil
        self.summarizedText = summarizedText
        self.llmInputTokens = llmInputTokens
        self.llmOutputTokens = llmOutputTokens
        self.llmModel = llmModel

        // Translation fields
        self.wasTranslated = translatedText != nil
        self.translatedText = translatedText
        self.translationInputTokens = translationInputTokens
        self.translationOutputTokens = translationOutputTokens
        self.translationModel = translationModel
        self.targetLanguage = targetLanguage

        // Calculate TTS cost
        self.ttsCost = TTSPricing.calculateCost(inputTokens: inputTokens)

        // Calculate LLM cost if applicable (summarization)
        if let llmIn = llmInputTokens, let llmOut = llmOutputTokens, let model = llmModel {
            self.llmCost = LLMPricing.calculateCost(
                inputTokens: llmIn,
                outputTokens: llmOut,
                model: model
            )
        } else {
            self.llmCost = nil
        }

        // Calculate translation cost if applicable (uses same LLM pricing)
        if let transIn = translationInputTokens, let transOut = translationOutputTokens, let model = translationModel {
            self.translationCost = LLMPricing.calculateCost(
                inputTokens: transIn,
                outputTokens: transOut,
                model: model
            )
        } else {
            self.translationCost = nil
        }

        // Total cost = TTS cost + LLM cost + translation cost
        self.cost = self.ttsCost + (self.llmCost ?? 0) + (self.translationCost ?? 0)
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

    var formattedTTSCost: String {
        String(format: "$%.6f", ttsCost)
    }

    var formattedLLMCost: String {
        if let llmCost = llmCost {
            return String(format: "$%.6f", llmCost)
        }
        return "-"
    }

    var formattedTranslationCost: String {
        if let translationCost = translationCost {
            return String(format: "$%.6f", translationCost)
        }
        return "-"
    }

    var ttsProvider: TTSProvider {
        voice.hasPrefix("elevenlabs:") ? .elevenLabs : .openAI
    }

    var ttsProviderDisplayName: String {
        ttsProvider.displayName
    }

    var truncatedText: String {
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }

    var displayText: String {
        // Priority: translated text > summarized text > original text
        if wasTranslated, let translated = translatedText {
            return translated
        } else if wasSummarized, let summarized = summarizedText {
            return summarized
        }
        return text
    }

    var targetLanguageDisplayName: String? {
        guard let lang = targetLanguage else { return nil }
        return TargetLanguage(rawValue: lang)?.displayName
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Calculate audio duration in seconds from file size
    /// Audio format: 24kHz, 16-bit mono = 48000 bytes/second
    func audioDuration(fileSize: Int64) -> TimeInterval {
        return Double(fileSize) / 48000.0
    }

    /// Format duration as mm:ss or h:mm:ss
    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

enum TTSPricing {
    // gpt-4o-mini-tts pricing: $0.60 per 1M input tokens
    static let costPerMillionTokens: Double = 0.60

    static func calculateCost(inputTokens: Int) -> Double {
        return Double(inputTokens) / 1_000_000.0 * costPerMillionTokens
    }
}

enum LLMPricing {
    // Pricing per 1M tokens
    // gpt-5-nano: $0.05 input, $0.40 output
    // gpt-5-mini: $0.25 input, $2.00 output
    // gpt-5.2: $1.75 input, $14.00 output

    static func calculateCost(inputTokens: Int, outputTokens: Int, model: String) -> Double {
        let inputCostPerMillion: Double
        let outputCostPerMillion: Double

        switch model {
        case "gpt-5-nano":
            inputCostPerMillion = 0.05
            outputCostPerMillion = 0.40
        case "gpt-5-mini":
            inputCostPerMillion = 0.25
            outputCostPerMillion = 2.00
        case "gpt-5.2":
            inputCostPerMillion = 1.75
            outputCostPerMillion = 14.00
        default:
            // Default to gpt-5-nano pricing
            inputCostPerMillion = 0.05
            outputCostPerMillion = 0.40
        }

        return Double(inputTokens) / 1_000_000.0 * inputCostPerMillion +
               Double(outputTokens) / 1_000_000.0 * outputCostPerMillion
    }
}
