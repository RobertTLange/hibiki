import Foundation

/// Handles incoming URL scheme requests from the CLI tool
final class CLIRequestHandler {
    static let shared = CLIRequestHandler()

    private let logger = DebugLogger.shared

    private init() {}

    /// Handle an incoming URL request from the CLI
    /// URL format: hibiki://speak?text=<text>&summarize=<bool>&prompt=<text>&translate=<lang>&display=<id>
    func handle(url: URL) {
        logger.debug("CLIRequestHandler received URL: \(url.absoluteString)", source: "CLI")

        guard url.scheme == "hibiki" else {
            logger.error("Invalid URL scheme: \(url.scheme ?? "nil")", source: "CLI")
            return
        }

        guard url.host == "speak" else {
            logger.error("Unknown URL host: \(url.host ?? "nil")", source: "CLI")
            return
        }

        // Parse query parameters
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            logger.error("Failed to parse URL components", source: "CLI")
            return
        }

        // Extract text parameter (required)
        guard let textItem = queryItems.first(where: { $0.name == "text" }),
              let text = textItem.value,
              !text.isEmpty else {
            logger.error("Missing or empty 'text' parameter", source: "CLI")
            return
        }

        // Extract summarize flag (optional, defaults to false)
        let shouldSummarize = queryItems.first(where: { $0.name == "summarize" })?.value == "true"

        // Extract summarization prompt (optional)
        let rawPrompt = queryItems.first(where: { $0.name == "prompt" })?.value
        let trimmedPrompt = rawPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summarizationPromptOverride = (trimmedPrompt?.isEmpty == false) ? rawPrompt : nil

        // Extract translate parameter (optional)
        let translateLang = queryItems.first(where: { $0.name == "translate" })?.value
        let targetLanguage: TargetLanguage?
        if let lang = translateLang {
            targetLanguage = parseLanguageCode(lang)
            if targetLanguage == nil {
                logger.error("Invalid language code: \(lang)", source: "CLI")
                return
            }
        } else {
            targetLanguage = nil
        }

        let promptLabel = summarizationPromptOverride == nil ? "default" : "custom"
        logger.info("CLI request: text=\(text.prefix(50))..., summarize=\(shouldSummarize), prompt=\(promptLabel), translate=\(translateLang ?? "none")", source: "CLI")

        // Process the request on the main actor
        Task { @MainActor in
            await AppState.shared.processTextFromCLI(
                text: text,
                shouldSummarize: shouldSummarize,
                targetLanguage: targetLanguage,
                summarizationPromptOverride: summarizationPromptOverride
            )
        }
    }

    /// Parse a language code string to TargetLanguage enum
    private func parseLanguageCode(_ code: String) -> TargetLanguage? {
        switch code.lowercased() {
        case "en", "english":
            return .english
        case "fr", "french":
            return .french
        case "de", "german":
            return .german
        case "ja", "japanese":
            return .japanese
        case "es", "spanish":
            return .spanish
        default:
            return nil
        }
    }
}
