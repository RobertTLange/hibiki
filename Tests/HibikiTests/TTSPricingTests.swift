import XCTest
@testable import Hibiki

final class TTSPricingTests: XCTestCase {
    private func configuration(_ provider: TTSProvider, elevenLabsModel: String = "") -> TTSConfiguration {
        TTSConfiguration(
            provider: provider,
            openAIAPIKey: "",
            openAIVoice: .coral,
            elevenLabsAPIKey: "",
            elevenLabsVoiceID: "voice",
            elevenLabsModelID: elevenLabsModel,
            pocketBaseURL: TTSConfiguration.defaultPocketBaseURL,
            pocketVoiceURL: TTSConfiguration.defaultPocketVoiceURL,
            pocketRequestTimeoutSec: TTSConfiguration.defaultPocketRequestTimeoutSec,
            instructions: TTSConfiguration.defaultInstructions
        )
    }

    /// Regression: OpenAI TTS was priced on input text alone, which is about 1% of the bill.
    func testOpenAIIncludesGeneratedAudio() {
        // One minute of speech from ~200 tokens of text.
        let cost = TTSPricing.cost(billing: .openAI, inputTokens: 200, audioSeconds: 60)
        XCTAssertEqual(cost, 0.00012 + 0.015, accuracy: 1e-9)

        let textOnly = TTSPricing.cost(billing: .openAI, inputTokens: 1_000_000, audioSeconds: 0)
        XCTAssertEqual(textOnly, 0.60, accuracy: 1e-9)
    }

    /// Regression: ElevenLabs was billed at OpenAI's per-token text rate.
    func testElevenLabsIsBilledPerCharacter() {
        // 2500 characters -> Hibiki counts 625 "tokens" (characters / 4).
        let standard = TTSPricing.cost(
            billing: .elevenLabs(costPerThousandCharacters: 0.10), inputTokens: 625, audioSeconds: 150
        )
        XCTAssertEqual(standard, 0.25, accuracy: 1e-9)

        let fast = TTSPricing.cost(
            billing: .elevenLabs(costPerThousandCharacters: 0.05), inputTokens: 625, audioSeconds: 150
        )
        XCTAssertEqual(fast, 0.125, accuracy: 1e-9)
    }

    func testLocalRuntimeIsFree() {
        XCTAssertEqual(TTSPricing.cost(billing: .local, inputTokens: 10_000, audioSeconds: 600), 0)
    }

    func testBillingFollowsProviderAndModel() {
        XCTAssertEqual(TTSPricing.billing(for: configuration(.openAI)), .openAI)
        XCTAssertEqual(TTSPricing.billing(for: configuration(.pocketLocal)), .local)

        for model in [ElevenLabsModel.elevenFlashV25, .elevenTurboV25] {
            XCTAssertEqual(
                TTSPricing.billing(for: configuration(.elevenLabs, elevenLabsModel: model.rawValue)),
                .elevenLabs(costPerThousandCharacters: 0.05),
                model.rawValue
            )
        }
        for model in [ElevenLabsModel.elevenMultilingualV2, .elevenV3] {
            XCTAssertEqual(
                TTSPricing.billing(for: configuration(.elevenLabs, elevenLabsModel: model.rawValue)),
                .elevenLabs(costPerThousandCharacters: 0.10),
                model.rawValue
            )
        }
    }

    func testEntryTotalAddsTTSAndLLMCosts() {
        let entry = HistoryEntry(
            text: "text",
            voice: "coral",
            inputTokens: 200,
            audioFileName: "a.pcm",
            ttsCost: 0.015,
            summarizedText: "summary",
            llmInputTokens: 1_000_000,
            llmOutputTokens: 0,
            llmModel: "gpt-5-nano"
        )
        XCTAssertEqual(entry.ttsCost, 0.015)
        XCTAssertEqual(entry.llmCost ?? 0, 0.05, accuracy: 1e-9)
        XCTAssertEqual(entry.cost, 0.065, accuracy: 1e-9)
    }
}
