import Foundation

enum TTSVoice: String, CaseIterable, Identifiable {
    case alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse
    var id: String { rawValue }
}

struct TTSResult {
    let audioData: Data
    let inputTokens: Int
    let isTokenEstimated: Bool  // true if tokens were estimated, false if from API
}

final class TTSService: NSObject {
    private var currentTask: URLSessionDataTask?
    private var session: URLSession?
    private var onAudioChunk: ((Data) -> Void)?
    private var onComplete: ((TTSResult) -> Void)?
    private var onError: ((Error) -> Void)?
    private var accumulatedAudioData = Data()
    private var inputTokens: Int = 0
    private var isTokenEstimated: Bool = false
    private var responseHeaders: [AnyHashable: Any] = [:]
    private var inputText: String = ""

    func streamSpeech(
        text: String,
        voice: TTSVoice,
        apiKey: String,
        instructions: String = "Speak naturally and clearly.",
        onAudioChunk: @escaping (Data) -> Void,
        onComplete: @escaping (TTSResult) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        print("[Hibiki] TTSService.streamSpeech called")
        print("[Hibiki] Text length: \(text.count), voice: \(voice.rawValue)")

        // Reset accumulated data for new request
        accumulatedAudioData = Data()
        inputTokens = 0
        isTokenEstimated = false
        responseHeaders = [:]
        inputText = text

        self.onAudioChunk = onAudioChunk
        self.onComplete = onComplete
        self.onError = onError

        guard !apiKey.isEmpty else {
            print("[Hibiki] ❌ API key is empty in TTSService")
            onError(TTSError.missingAPIKey)
            return
        }

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("[Hibiki] ❌ Invalid URL")
            onError(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": voice.rawValue,
            "instructions": instructions,
            "response_format": "pcm"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Hibiki] ❌ JSON encoding error: \(error)")
            onError(error)
            return
        }

        print("[Hibiki] 🌐 Making API request to OpenAI...")

        // Create session with delegate for streaming
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        currentTask = session?.dataTask(with: request)
        currentTask?.resume()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
    }
}

extension TTSService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        print("[Hibiki] 📦 Received data chunk: \(data.count) bytes")
        accumulatedAudioData.append(data)
        onAudioChunk?(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Check if it's a cancellation
            if (error as NSError).code == NSURLErrorCancelled {
                print("[Hibiki] Request cancelled")
                accumulatedAudioData = Data()
                inputTokens = 0
                isTokenEstimated = false
                inputText = ""
                return
            }
            print("[Hibiki] ❌ Network error: \(error.localizedDescription)")
            accumulatedAudioData = Data()
            inputTokens = 0
            isTokenEstimated = false
            inputText = ""
            onError?(error)
        } else {
            // Try to parse the response for usage info (fallback check)
            parseResponseForUsage()
            
            // If we still don't have tokens from headers or body, estimate from input text
            if inputTokens == 0 && !inputText.isEmpty {
                // Rough estimation: ~4 characters per token for English text
                // This is a common approximation for GPT tokenizers
                inputTokens = max(1, inputText.count / 4)
                isTokenEstimated = true
                print("[Hibiki] 📊 Estimated input tokens from text length: \(inputTokens) (from \(inputText.count) chars)")
            }

            print("[Hibiki] ✅ Request completed successfully, total audio: \(accumulatedAudioData.count) bytes, inputTokens: \(inputTokens)\(isTokenEstimated ? " (estimated)" : "")")
            let result = TTSResult(audioData: accumulatedAudioData, inputTokens: inputTokens, isTokenEstimated: isTokenEstimated)
            accumulatedAudioData = Data()
            inputTokens = 0
            isTokenEstimated = false
            inputText = ""
            onComplete?(result)
        }
    }

    private func parseResponseForUsage() {
        // For TTS API, usage info comes from HTTP headers (extracted in extractUsageFromHeaders)
        // The response body contains raw audio data, not JSON
        // This method is kept for compatibility but usage is already extracted from headers
        
        // If we still don't have tokens, it means the header wasn't present
        // Log for debugging purposes
        if inputTokens == 0 {
            print("[Hibiki] ⚠️ Input tokens still 0 - checking if response body contains error JSON")
            
            // Only try to parse as JSON if it looks like an error response (not binary audio)
            if let responseString = String(data: accumulatedAudioData, encoding: .utf8),
               responseString.hasPrefix("{") {
                let preview = String(responseString.prefix(500))
                print("[Hibiki] 📄 Response preview (possible error): \(preview)")
                
                if let json = try? JSONSerialization.jsonObject(with: accumulatedAudioData) as? [String: Any] {
                    // Check for error response
                    if let error = json["error"] as? [String: Any] {
                        print("[Hibiki] ❌ API returned error in body: \(error)")
                    }
                    // Check for usage in body (unlikely for TTS but just in case)
                    if let usage = json["usage"] as? [String: Any],
                       let tokens = usage["input_tokens"] as? Int {
                        inputTokens = tokens
                        print("[Hibiki] 📊 Input tokens from response body: \(inputTokens)")
                    }
                }
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            print("[Hibiki] 📡 HTTP response: \(httpResponse.statusCode)")
            print("[Hibiki] 📡 Content-Type: \(httpResponse.allHeaderFields["Content-Type"] ?? "unknown")")

            // Store headers for later usage extraction
            responseHeaders = httpResponse.allHeaderFields

            // Log all headers for debugging
            print("[Hibiki] 📡 Response headers:")
            for (key, value) in httpResponse.allHeaderFields {
                print("[Hibiki]   \(key): \(value)")
            }

            // Extract usage from headers if available
            // OpenAI TTS returns usage in x-openai-* headers
            extractUsageFromHeaders(httpResponse.allHeaderFields)

            if httpResponse.statusCode != 200 {
                print("[Hibiki] ❌ API error: HTTP \(httpResponse.statusCode)")
                onError?(TTSError.apiError(statusCode: httpResponse.statusCode))
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }

    private func extractUsageFromHeaders(_ headers: [AnyHashable: Any]) {
        // OpenAI returns usage info in various header formats
        // Check for common patterns (case-insensitive lookup)
        let headerDict = Dictionary(uniqueKeysWithValues: headers.map { 
            (String(describing: $0.key).lowercased(), $0.value) 
        })
        
        // Try different possible header names for input tokens USED in this request
        // NOTE: Do NOT include rate limit headers like x-ratelimit-remaining-tokens
        // as those show quota remaining, not tokens used
        let possibleTokenHeaders = [
            "x-openai-input-tokens",
            "openai-input-tokens", 
            "x-input-tokens",
            "x-request-input-tokens",
            "openai-processing-tokens"
        ]
        
        for headerName in possibleTokenHeaders {
            if let value = headerDict[headerName] {
                if let intValue = value as? Int {
                    inputTokens = intValue
                    print("[Hibiki] 📊 Input tokens from header '\(headerName)': \(inputTokens)")
                    return
                } else if let stringValue = value as? String, let intValue = Int(stringValue) {
                    inputTokens = intValue
                    print("[Hibiki] 📊 Input tokens from header '\(headerName)': \(inputTokens)")
                    return
                }
            }
        }
        
        // Log available headers for debugging to help identify the correct one
        print("[Hibiki] ⚠️ No input token header found. Available headers with numeric values:")
        for (key, value) in headerDict {
            if let strVal = value as? String, Int(strVal) != nil {
                print("[Hibiki]   - \(key): \(strVal)")
            } else if value is Int {
                print("[Hibiki]   - \(key): \(value)")
            }
        }
    }
}

enum TTSError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case apiError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let statusCode):
            return "API error: HTTP \(statusCode)"
        }
    }
}
