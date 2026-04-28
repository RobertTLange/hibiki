import Foundation

public enum MistralLocalTTSDefaults {
    public static let baseURL = "http://127.0.0.1:8091"
    public static let modelID = "mistralai/Voxtral-4B-TTS-2603"
    public static let mlxModelID = "mlx-community/Voxtral-4B-TTS-2603-mlx-bf16"
    public static let voice = "casual_male"
    public static let requestTimeoutSec: Double = 180
}

public struct MistralLocalTTSConfiguration: Equatable, Sendable {
    public let mistralLocalBaseURL: String
    public let mistralLocalModelID: String
    public let mistralLocalVoice: String

    public init(
        mistralLocalBaseURL: String,
        mistralLocalModelID: String,
        mistralLocalVoice: String
    ) {
        self.mistralLocalBaseURL = mistralLocalBaseURL
        self.mistralLocalModelID = mistralLocalModelID
        self.mistralLocalVoice = mistralLocalVoice
    }

    public var normalizedBaseURL: String {
        let trimmed = mistralLocalBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return MistralLocalTTSDefaults.baseURL }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    public var normalizedModelID: String {
        let trimmed = mistralLocalModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MistralLocalTTSDefaults.modelID : trimmed
    }

    public var normalizedVoice: String {
        let trimmed = mistralLocalVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MistralLocalTTSDefaults.voice : trimmed
    }

    public var historyVoiceLabel: String {
        "\(LocalTTSVoiceLabel.mistralPrefix)\(normalizedVoice)"
    }

    public var speechURL: URL? {
        guard var components = URLComponents(string: normalizedBaseURL) else { return nil }
        let path = components.path
        if path.isEmpty || path == "/" {
            components.path = "/v1/audio/speech"
        } else if path.hasSuffix("/v1/audio/speech") {
            return components.url
        } else if path.hasSuffix("/v1") {
            components.path = "\(path)/audio/speech"
        } else {
            components.path = path.hasSuffix("/") ? "\(path)v1/audio/speech" : "\(path)/v1/audio/speech"
        }
        return components.url
    }
}

public enum LocalTTSVoiceLabel {
    public static let pocketPrefix = "pocket:"
    public static let mistralPrefix = "mistral:"

    public static func isLocal(_ voice: String) -> Bool {
        isPocket(voice) || isMistral(voice)
    }

    public static func isPocket(_ voice: String) -> Bool {
        voice.hasPrefix(pocketPrefix)
    }

    public static func isMistral(_ voice: String) -> Bool {
        voice.hasPrefix(mistralPrefix)
    }
}
