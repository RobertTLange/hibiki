import Foundation

struct LLMResult {
    let summarizedText: String
    let inputTokens: Int
    let outputTokens: Int
    let model: String
}

enum LLMModel: String, CaseIterable, Identifiable {
    case gpt5Nano = "gpt-5-nano"
    case gpt5Mini = "gpt-5-mini"
    case gpt52 = "gpt-5.2"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt5Nano: return "GPT-5 Nano"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt52: return "GPT-5.2"
        }
    }
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case apiError(statusCode: Int, message: String?)
    case decodingError
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let code, let msg):
            return "API error: HTTP \(code)\(msg.map { " - \($0)" } ?? "")"
        case .decodingError:
            return "Failed to decode API response"
        case .emptyResponse:
            return "LLM returned empty response"
        }
    }
}

final class LLMService {
    private let logger = DebugLogger.shared
    private var currentTask: URLSessionTask?

    func summarize(
        text: String,
        model: LLMModel,
        systemPrompt: String,
        apiKey: String
    ) async throws -> LLMResult {
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw LLMError.invalidURL
        }

        logger.info("Starting LLM summarization with model: \(model.rawValue)", source: "LLMService")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // 60 second timeout

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_completion_tokens": 8192
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        logger.info("Sending request to OpenAI API...", source: "LLMService")

        let (data, response) = try await URLSession.shared.data(for: request)
        
        logger.info("Received response from OpenAI API (\(data.count) bytes)", source: "LLMService")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: 0, message: "Invalid response")
        }

        logger.info("LLM API response status: \(httpResponse.statusCode)", source: "LLMService")
        
        // Log raw response for debugging
        if let rawResponse = String(data: data, encoding: .utf8) {
            logger.info("LLM raw response: \(rawResponse.prefix(2000))", source: "LLMService")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (errorMessage?["error"] as? [String: Any])?["message"] as? String
            logger.error("LLM API error: HTTP \(httpResponse.statusCode) - \(message ?? "unknown")", source: "LLMService")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Failed to parse JSON response", source: "LLMService")
            throw LLMError.decodingError
        }
        
        guard let choices = json["choices"] as? [[String: Any]], !choices.isEmpty else {
            logger.error("No choices in response. Keys: \(json.keys.sorted())", source: "LLMService")
            throw LLMError.decodingError
        }
        
        let firstChoice = choices[0]
        logger.debug("First choice keys: \(firstChoice.keys.sorted())", source: "LLMService")
        
        guard let message = firstChoice["message"] as? [String: Any] else {
            logger.error("No message in first choice. Choice: \(firstChoice)", source: "LLMService")
            throw LLMError.decodingError
        }
        
        logger.debug("Message keys: \(message.keys.sorted())", source: "LLMService")
        
        // Try to get content - it might be nil or empty in some cases
        let content: String
        if let messageContent = message["content"] as? String {
            logger.info("Got content string, length: \(messageContent.count), value: '\(messageContent.prefix(500))'", source: "LLMService")
            content = messageContent
        } else if message["content"] == nil || message["content"] is NSNull {
            // Content is null - check for refusal or other fields
            if let refusal = message["refusal"] as? String, !refusal.isEmpty {
                logger.error("LLM refused request: \(refusal)", source: "LLMService")
                throw LLMError.apiError(statusCode: 200, message: "Request refused: \(refusal)")
            }
            logger.error("Message content is null. Full message: \(message)", source: "LLMService")
            throw LLMError.emptyResponse
        } else {
            logger.error("Content is not a string. Type: \(type(of: message["content"]))", source: "LLMService")
            throw LLMError.decodingError
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            logger.error("LLM returned empty content after trimming. Original length: \(content.count)", source: "LLMService")
            throw LLMError.emptyResponse
        }

        // Extract usage
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        logger.info("LLM summarization complete: \(trimmedContent.count) chars, \(inputTokens) input tokens, \(outputTokens) output tokens", source: "LLMService")

        return LLMResult(
            summarizedText: trimmedContent,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model.rawValue
        )
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    /// Streaming summarization - yields text chunks as they arrive
    func summarizeStreaming(
        text: String,
        model: LLMModel,
        systemPrompt: String,
        apiKey: String,
        onChunk: @escaping (String) -> Void
    ) async throws -> LLMResult {
        guard !apiKey.isEmpty else {
            throw LLMError.missingAPIKey
        }
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw LLMError.invalidURL
        }
        
        logger.info("Starting streaming LLM summarization with model: \(model.rawValue)", source: "LLMService")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // Longer timeout for streaming
        
        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_completion_tokens": 8192,
            "stream": true,
            "stream_options": ["include_usage": true]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        logger.info("Sending streaming request to OpenAI API...", source: "LLMService")
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.apiError(statusCode: 0, message: "Invalid response")
        }
        
        logger.info("Streaming response status: \(httpResponse.statusCode)", source: "LLMService")
        
        guard httpResponse.statusCode == 200 else {
            // For error responses, we need to collect all bytes
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorMessage = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any]
            let message = (errorMessage?["error"] as? [String: Any])?["message"] as? String
            logger.error("LLM API error: HTTP \(httpResponse.statusCode) - \(message ?? "unknown")", source: "LLMService")
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
        
        var fullContent = ""
        var inputTokens = 0
        var outputTokens = 0
        
        // Process SSE stream
        for try await line in bytes.lines {
            // Skip empty lines and comments
            guard line.hasPrefix("data: ") else { continue }
            
            let jsonString = String(line.dropFirst(6)) // Remove "data: " prefix
            
            // Check for stream end
            if jsonString == "[DONE]" {
                logger.debug("Stream complete signal received", source: "LLMService")
                break
            }
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }
            
            // Extract usage from final chunk (when stream_options.include_usage is true)
            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
            }
            
            // Extract content delta
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let delta = firstChoice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                fullContent += content
                logger.debug("Stream chunk: '\(content)'", source: "LLMService")
                
                // Call the chunk handler on main thread
                await MainActor.run {
                    onChunk(content)
                }
            }
        }
        
        let trimmedContent = fullContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            logger.error("Streaming LLM returned empty content", source: "LLMService")
            throw LLMError.emptyResponse
        }
        
        logger.info("Streaming summarization complete: \(trimmedContent.count) chars, \(inputTokens) input tokens, \(outputTokens) output tokens", source: "LLMService")
        
        return LLMResult(
            summarizedText: trimmedContent,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            model: model.rawValue
        )
    }
}
