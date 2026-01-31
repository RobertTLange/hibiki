import Foundation

public enum CLIRequestError: Error, Equatable {
    case emptyText
    case invalidLanguage(String)
    case promptWithoutSummarize
    case emptyPrompt
    case invalidURL
}

public struct CLIRequest {
    public let text: String
    public let summarize: Bool
    public let translate: String?
    public let prompt: String?

    private static let validLanguages = ["en", "fr", "de", "ja", "es"]

    public init(text: String, summarize: Bool, translate: String?, prompt: String?) {
        self.text = text
        self.summarize = summarize
        self.translate = translate
        self.prompt = prompt
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
        }
    }
}
