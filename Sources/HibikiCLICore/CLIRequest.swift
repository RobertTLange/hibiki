import Foundation

public enum CLIRequestError: Error, Equatable {
    case emptyText
    case invalidLanguage(String)
    case promptWithoutSummarize
    case emptyPrompt
    case invalidURL
    case unsupportedURL
    case urlTooLong(bytes: Int)
}

public struct CLIRequest {
    public let text: String
    public let summarize: Bool
    public let translate: String?
    public let prompt: String?

    private static let validLanguages = ["en", "fr", "de", "ja", "es"]

    /// Largest URL the CLI will send.
    public static let maxCLIURLBytes = 32_000
    /// Largest URL the app accepts. Looser than the CLI limit so direct `open hibiki://…`
    /// callers near that limit keep working, while still bounding what a stray link or
    /// another app can make Hibiki synthesize.
    public static let maxAcceptedURLBytes = 64_000

    public init(text: String, summarize: Bool, translate: String?, prompt: String?) {
        self.text = text
        self.summarize = summarize
        self.translate = translate
        self.prompt = prompt
    }

    /// Decode a `hibiki://speak` URL received by the app (inverse of `url()`).
    /// The translate value is passed through untouched; the app maps it to a language.
    public init(url: URL) throws {
        guard url.scheme == "hibiki", url.host == "speak" else {
            throw CLIRequestError.unsupportedURL
        }

        let byteCount = url.absoluteString.utf8.count
        guard byteCount <= Self.maxAcceptedURLBytes else {
            throw CLIRequestError.urlTooLong(bytes: byteCount)
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let text = value("text"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIRequestError.emptyText
        }

        let prompt = value("prompt")
        let hasPrompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        self.init(
            text: text,
            summarize: value("summarize") == "true",
            translate: value("translate"),
            prompt: hasPrompt ? prompt : nil
        )
    }

    public func validate() throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIRequestError.emptyText
        }

        if let lang = translate {
            let normalized = lang.lowercased()
            guard Self.validLanguages.contains(normalized) else {
                throw CLIRequestError.invalidLanguage(lang)
            }
        }

        if let prompt = prompt {
            if !summarize {
                throw CLIRequestError.promptWithoutSummarize
            }
            if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CLIRequestError.emptyPrompt
            }
        }
    }

    public func url() throws -> URL {
        try validate()

        var components = URLComponents()
        components.scheme = "hibiki"
        components.host = "speak"

        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "text", value: text))

        if summarize {
            queryItems.append(URLQueryItem(name: "summarize", value: "true"))
        }

        if let prompt = prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "prompt", value: prompt))
        }

        if let lang = translate {
            queryItems.append(URLQueryItem(name: "translate", value: lang.lowercased()))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw CLIRequestError.invalidURL
        }

        return url
    }
}

public extension CLIRequestError {
    var userMessage: String {
        switch self {
        case .emptyText:
            return "Text cannot be empty"
        case .invalidLanguage(let lang):
            return "Invalid language code '\(lang)'. Use: en, fr, de, ja, es"
        case .promptWithoutSummarize:
            return "Prompt requires --summarize"
        case .emptyPrompt:
            return "Prompt cannot be empty"
        case .invalidURL:
            return "Failed to construct request URL"
        case .unsupportedURL:
            return "Not a hibiki://speak URL"
        case .urlTooLong(let bytes):
            return "Request URL is too long (\(bytes) bytes; limit \(CLIRequest.maxAcceptedURLBytes))"
        }
    }
}
