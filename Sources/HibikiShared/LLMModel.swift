import Foundation

public enum LLMModel: String, CaseIterable, Identifiable, Sendable {
    case gpt6Luna = "gpt-6-luna"
    case gpt5Nano = "gpt-5-nano"
    case gpt5Mini = "gpt-5-mini"
    case gpt52 = "gpt-5.2"

    public static let defaultModel: LLMModel = .gpt5Nano

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gpt6Luna: return "GPT-6 Luna"
        case .gpt5Nano: return "GPT-5 Nano"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt52: return "GPT-5.2"
        }
    }

    /// USD per 1M tokens.
    public var pricing: (input: Double, output: Double) {
        switch self {
        case .gpt6Luna: return (0.10, 0.50)
        case .gpt5Nano: return (0.05, 0.40)
        case .gpt5Mini: return (0.25, 2.00)
        case .gpt52: return (1.75, 14.00)
        }
    }
}

public enum LLMPricing {
    /// Unknown model identifiers are billed at the default model's rate.
    public static func calculateCost(inputTokens: Int, outputTokens: Int, model: String) -> Double {
        let pricing = (LLMModel(rawValue: model) ?? .defaultModel).pricing
        return Double(inputTokens) / 1_000_000.0 * pricing.input +
               Double(outputTokens) / 1_000_000.0 * pricing.output
    }
}
