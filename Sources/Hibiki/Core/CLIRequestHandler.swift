import Foundation
import HibikiCLICore

/// Handles incoming URL scheme requests from the CLI tool
final class CLIRequestHandler {
    static let shared = CLIRequestHandler()

    private let logger = DebugLogger.shared

    private init() {}

    /// Handle an incoming URL request from the CLI
    /// URL format: hibiki://speak?text=<text>&summarize=<bool>&prompt=<text>&translate=<lang>&display=<id>
    func handle(url: URL) {
        logger.debug("CLIRequestHandler received URL (\(url.absoluteString.utf8.count) bytes)", source: "CLI")

        // Anything on the machine (or a clicked link) can open this URL scheme, so the
        // request is validated and bounded here, not just in the CLI.
        let request: CLIRequest
        do {
            request = try CLIRequest(url: url)
        } catch let error as CLIRequestError {
            logger.error("Rejected URL request: \(error.userMessage)", source: "CLI")
            return
        } catch {
            logger.error("Rejected URL request: \(error.localizedDescription)", source: "CLI")
            return
        }

        let text = request.text
        let shouldSummarize = request.summarize
        let summarizationPromptOverride = request.prompt

        // Extract translate parameter (optional)
        let translateLang = request.translate
        let targetLanguage: TargetLanguage?
        if let lang = translateLang {
            targetLanguage = parseLanguageCode(lang)
            if targetLanguage == nil {
                logger.error("Invalid language code: \(lang.prefix(16))", source: "CLI")
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
