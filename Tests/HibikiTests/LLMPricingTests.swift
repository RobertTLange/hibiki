import XCTest
import HibikiShared

final class LLMPricingTests: XCTestCase {
    private let oneMillion = 1_000_000

    func testGPT6LunaPricing() {
        let cost = LLMPricing.calculateCost(inputTokens: oneMillion, outputTokens: oneMillion, model: "gpt-6-luna")
        XCTAssertEqual(cost, 0.60, accuracy: 1e-9)
    }

    func testGPT6LunaIsListedFirst() {
        XCTAssertEqual(LLMModel.allCases.first, .gpt6Luna)
        XCTAssertEqual(LLMModel.gpt6Luna.displayName, "GPT-6 Luna")
    }

    func testNanoPricing() {
        let cost = LLMPricing.calculateCost(inputTokens: oneMillion, outputTokens: oneMillion, model: "gpt-5-nano")
        XCTAssertEqual(cost, 0.45, accuracy: 1e-9)
    }

    func testMiniPricing() {
        let cost = LLMPricing.calculateCost(inputTokens: oneMillion, outputTokens: oneMillion, model: "gpt-5-mini")
        XCTAssertEqual(cost, 2.25, accuracy: 1e-9)
    }

    func testGPT52Pricing() {
        let cost = LLMPricing.calculateCost(inputTokens: oneMillion, outputTokens: oneMillion, model: "gpt-5.2")
        XCTAssertEqual(cost, 15.75, accuracy: 1e-9)
    }

    func testUnknownModelFallsBackToDefaultModelPricing() {
        let unknown = LLMPricing.calculateCost(inputTokens: oneMillion, outputTokens: oneMillion, model: "unknown")
        let fallback = LLMPricing.calculateCost(
            inputTokens: oneMillion, outputTokens: oneMillion, model: LLMModel.defaultModel.rawValue
        )
        XCTAssertEqual(unknown, fallback, accuracy: 1e-9)
    }

    func testModelRawValuesRoundTrip() {
        for model in LLMModel.allCases {
            XCTAssertEqual(LLMModel(rawValue: model.rawValue), model)
        }
    }

    func testDefaultModelIsGPT6Luna() {
        XCTAssertEqual(LLMModel.defaultModel, .gpt6Luna)
    }
}
