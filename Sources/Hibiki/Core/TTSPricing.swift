import Foundation

/// How a TTS request is billed by its provider.
enum TTSBilling: Equatable, Sendable {
    /// OpenAI `gpt-4o-mini-tts`: text input tokens plus generated audio.
    case openAI
    /// ElevenLabs: per character sent.
    case elevenLabs(costPerThousandCharacters: Double)
    /// Local Pocket runtime: nothing is billed.
    case local
}

/// TTS list prices in USD. These are estimates for the statistics view, not invoices:
/// check the providers' pricing pages when the numbers matter.
enum TTSPricing {
    /// gpt-4o-mini-tts text input: $0.60 per 1M tokens.
    static let openAIInputCostPerMillionTokens: Double = 0.60

    /// gpt-4o-mini-tts audio output is billed at $12 per 1M audio tokens. The speech endpoint
    /// does not report how many it used, so the audio that came back is priced at the
    /// commonly quoted equivalent of about $0.015 per minute. This is the dominant part of
    /// the bill: a minute of speech is roughly 200 input tokens, i.e. $0.00012 of text.
    static let openAIAudioCostPerMinute: Double = 0.015

    /// ElevenLabs API rate card: Multilingual v2 / v3.
    static let elevenLabsStandardCostPerThousandCharacters: Double = 0.10
    /// ElevenLabs API rate card: Flash / Turbo.
    static let elevenLabsFastCostPerThousandCharacters: Double = 0.05

    static func billing(for configuration: TTSConfiguration) -> TTSBilling {
        switch configuration.provider {
        case .openAI:
            return .openAI
        case .pocketLocal:
            return .local
        case .elevenLabs:
            switch ElevenLabsModel(rawValue: configuration.normalizedElevenLabsModelID) {
            case .elevenFlashV25, .elevenTurboV25:
                return .elevenLabs(costPerThousandCharacters: elevenLabsFastCostPerThousandCharacters)
            case .elevenV3, .elevenMultilingualV2, .none:
                return .elevenLabs(costPerThousandCharacters: elevenLabsStandardCostPerThousandCharacters)
            }
        }
    }

    /// - Parameters:
    ///   - inputTokens: tokens sent to the provider. ElevenLabs reports no usage, so for it
    ///     Hibiki counts characters / 4 per request; characters are recovered as tokens x 4.
    ///     Using what was actually sent keeps a request that was stopped early from being
    ///     billed for text that never left the app.
    ///   - audioSeconds: duration of the audio received.
    static func cost(billing: TTSBilling, inputTokens: Int, audioSeconds: Double) -> Double {
        switch billing {
        case .openAI:
            return Double(inputTokens) / 1_000_000.0 * openAIInputCostPerMillionTokens
                + max(0, audioSeconds) / 60.0 * openAIAudioCostPerMinute
        case .elevenLabs(let costPerThousandCharacters):
            return Double(inputTokens * 4) / 1_000.0 * costPerThousandCharacters
        case .local:
            return 0
        }
    }
}
