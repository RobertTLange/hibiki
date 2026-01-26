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
    private var receivedChunkCount: Int = 0
    private var receivedChunkBytes: Int = 0

    // Multi-chunk processing state
    private var chunks: [String] = []
    private var currentChunkIndex: Int = 0
    private var totalInputTokens: Int = 0
    private var isCancelled: Bool = false
    private var currentVoice: TTSVoice = .coral
    private var currentApiKey: String = ""
    private var currentInstructions: String = ""

    // Pipeline queue state for interleaved processing
    private var sentenceQueue: [String] = []
    private var isProcessingSentence: Bool = false
    private var allSentencesEnqueued: Bool = false
    private var pipelineOnAudioChunk: ((Data) -> Void)?
    private var pipelineOnSentenceComplete: ((Int) -> Void)?  // Called with token count
    private var pipelineOnAllComplete: ((Int) -> Void)?  // Called with total tokens
    private var pipelineOnError: ((Error) -> Void)?
    private var pipelineTotalTokens: Int = 0
    private let pipelineQueue = DispatchQueue(label: "com.hibiki.tts.pipeline")

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

        // Reset all state for new request
        accumulatedAudioData = Data()
        inputTokens = 0
        totalInputTokens = 0
        isTokenEstimated = false
        responseHeaders = [:]
        isCancelled = false
        receivedChunkCount = 0
        receivedChunkBytes = 0

        self.onAudioChunk = onAudioChunk
        self.onComplete = onComplete
        self.onError = onError

        guard !apiKey.isEmpty else {
            print("[Hibiki] ❌ API key is empty in TTSService")
            onError(TTSError.missingAPIKey)
            return
        }

        // Split text into chunks for processing
        chunks = TextChunker.chunk(text)
        currentChunkIndex = 0

        print("[Hibiki] 📝 Split text into \(chunks.count) chunk(s)")
        for (i, chunk) in chunks.enumerated() {
            print("[Hibiki]   Chunk \(i + 1): \(chunk.count) chars")
        }

        guard !chunks.isEmpty else {
            print("[Hibiki] ⚠️ No chunks to process (empty text)")
            onComplete(TTSResult(audioData: Data(), inputTokens: 0, isTokenEstimated: false))
            return
        }

        // Store parameters for sequential chunk processing
        currentVoice = voice
        currentApiKey = apiKey
        currentInstructions = instructions

        // Start processing first chunk
        processNextChunk()
    }

    /// Process the next chunk in the queue
    private func processNextChunk() {
        guard !isCancelled else {
            print("[Hibiki] ⚠️ Chunk processing cancelled")
            return
        }

        guard currentChunkIndex < chunks.count else {
            // All chunks complete
            print("[Hibiki] ✅ All \(chunks.count) chunk(s) complete, total tokens: \(totalInputTokens)")
            let result = TTSResult(
                audioData: accumulatedAudioData,
                inputTokens: totalInputTokens,
                isTokenEstimated: isTokenEstimated
            )
            accumulatedAudioData = Data()
            totalInputTokens = 0
            onComplete?(result)
            return
        }

        let chunkText = chunks[currentChunkIndex]
        print("[Hibiki] 🔄 Processing chunk \(currentChunkIndex + 1)/\(chunks.count) (\(chunkText.count) chars)")

        streamSingleChunk(text: chunkText)
    }

    /// Stream a single chunk of text to the TTS API
    private func streamSingleChunk(text: String) {
        inputText = text  // Store for token estimation fallback

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("[Hibiki] ❌ Invalid URL")
            onError?(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(currentApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": currentVoice.rawValue,
            "instructions": currentInstructions,
            "response_format": "pcm"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Hibiki] ❌ JSON encoding error: \(error)")
            onError?(error)
            return
        }

        print("[Hibiki] 🌐 Making API request to OpenAI for chunk \(currentChunkIndex + 1)...")

        // Create session with delegate for streaming
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        currentTask = session?.dataTask(with: request)
        currentTask?.resume()
    }

    func cancel() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
        session?.invalidateAndCancel()
        session = nil
        // Reset chunk state
        chunks = []
        currentChunkIndex = 0
        totalInputTokens = 0
        // Reset pipeline state
        pipelineQueue.sync {
            sentenceQueue = []
            isProcessingSentence = false
            allSentencesEnqueued = false
            pipelineTotalTokens = 0
        }
    }

    // MARK: - Pipeline API for Interleaved Processing

    /// Start a new pipeline session for interleaved TTS processing.
    /// Call enqueueSentence() to add sentences, then markAllSentencesEnqueued() when done.
    /// - Parameters:
    ///   - voice: TTS voice to use
    ///   - apiKey: OpenAI API key
    ///   - instructions: TTS instructions
    ///   - onAudioChunk: Called for each audio chunk received
    ///   - onSentenceComplete: Called when a sentence finishes (with token count)
    ///   - onAllComplete: Called when all sentences are processed (with total tokens)
    ///   - onError: Called on error
    func startPipeline(
        voice: TTSVoice,
        apiKey: String,
        instructions: String = "Speak naturally and clearly.",
        onAudioChunk: @escaping (Data) -> Void,
        onSentenceComplete: @escaping (Int) -> Void,
        onAllComplete: @escaping (Int) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        print("[Hibiki] TTSService.startPipeline called")

        // Reset pipeline state
        pipelineQueue.sync {
            sentenceQueue = []
            isProcessingSentence = false
            allSentencesEnqueued = false
            pipelineTotalTokens = 0
        }

        isCancelled = false
        currentVoice = voice
        currentApiKey = apiKey
        currentInstructions = instructions
        pipelineOnAudioChunk = onAudioChunk
        pipelineOnSentenceComplete = onSentenceComplete
        pipelineOnAllComplete = onAllComplete
        pipelineOnError = onError
        accumulatedAudioData = Data()

        guard !apiKey.isEmpty else {
            print("[Hibiki] ❌ API key is empty in TTSService pipeline")
            onError(TTSError.missingAPIKey)
            return
        }
    }

    /// Enqueue a sentence for TTS processing in the pipeline.
    /// Sentences are processed sequentially in order.
    /// - Parameter sentence: The sentence to speak
    func enqueueSentence(_ sentence: String) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        print("[Hibiki] 📝 Enqueueing sentence for TTS: \(trimmed.prefix(50))...")

        pipelineQueue.sync {
            sentenceQueue.append(trimmed)
        }

        processNextSentenceIfNeeded()
    }

    /// Mark that all sentences have been enqueued.
    /// The pipeline will complete after processing remaining sentences.
    func markAllSentencesEnqueued() {
        print("[Hibiki] 🏁 All sentences enqueued")
        pipelineQueue.sync {
            allSentencesEnqueued = true
        }
        processNextSentenceIfNeeded()
    }

    /// Process the next sentence in the queue if not already processing
    private func processNextSentenceIfNeeded() {
        var shouldProcess = false
        var sentence: String?
        var shouldComplete = false

        pipelineQueue.sync {
            if isCancelled {
                return
            }

            if !isProcessingSentence && !sentenceQueue.isEmpty {
                isProcessingSentence = true
                sentence = sentenceQueue.removeFirst()
                shouldProcess = true
            } else if !isProcessingSentence && sentenceQueue.isEmpty && allSentencesEnqueued {
                shouldComplete = true
            }
        }

        if shouldComplete {
            print("[Hibiki] ✅ Pipeline complete, total tokens: \(pipelineTotalTokens)")
            pipelineOnAllComplete?(pipelineTotalTokens)
            return
        }

        if shouldProcess, let text = sentence {
            streamPipelineSentence(text: text)
        }
    }

    /// Stream a single sentence in the pipeline
    private func streamPipelineSentence(text: String) {
        print("[Hibiki] 🔄 Processing pipeline sentence (\(text.count) chars)")

        inputText = text

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("[Hibiki] ❌ Invalid URL")
            pipelineOnError?(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(currentApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": currentVoice.rawValue,
            "instructions": currentInstructions,
            "response_format": "pcm"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Hibiki] ❌ JSON encoding error: \(error)")
            pipelineOnError?(error)
            return
        }

        // Use shared URL session for pipeline to avoid delegate issues
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if self.isCancelled {
                return
            }

            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("[Hibiki] ❌ Pipeline TTS error: \(error.localizedDescription)")
                    self.pipelineOnError?(error)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.pipelineOnError?(TTSError.apiError(statusCode: 0))
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("[Hibiki] ❌ Pipeline TTS API error: HTTP \(httpResponse.statusCode)")
                self.pipelineOnError?(TTSError.apiError(statusCode: httpResponse.statusCode))
                return
            }

            guard let audioData = data, !audioData.isEmpty else {
                print("[Hibiki] ⚠️ Pipeline TTS returned empty data")
                self.finishCurrentSentence(tokens: 0)
                return
            }

            // Estimate tokens from text length
            let estimatedTokens = max(1, text.count / 4)

            print("[Hibiki] ✅ Pipeline sentence complete: \(audioData.count) bytes, ~\(estimatedTokens) tokens")

            // Deliver audio chunk
            self.pipelineOnAudioChunk?(audioData)

            // Update totals and signal completion
            self.finishCurrentSentence(tokens: estimatedTokens)
        }

        task.resume()
    }

    /// Mark current sentence as complete and process next
    private func finishCurrentSentence(tokens: Int) {
        pipelineQueue.sync {
            pipelineTotalTokens += tokens
            isProcessingSentence = false
        }

        pipelineOnSentenceComplete?(tokens)
        processNextSentenceIfNeeded()
    }
}

extension TTSService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedChunkCount += 1
        receivedChunkBytes += data.count
        if receivedChunkCount == 1 || receivedChunkCount % 20 == 0 {
            print("[Hibiki] 📦 Received \(receivedChunkCount) chunk(s), \(receivedChunkBytes) bytes total")
        }
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
                totalInputTokens = 0
                isTokenEstimated = false
                inputText = ""
                chunks = []
                currentChunkIndex = 0
                return
            }
            print("[Hibiki] ❌ Network error: \(error.localizedDescription)")
            accumulatedAudioData = Data()
            inputTokens = 0
            totalInputTokens = 0
            isTokenEstimated = false
            inputText = ""
            chunks = []
            currentChunkIndex = 0
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

            // Accumulate tokens from this chunk
            totalInputTokens += inputTokens
            print("[Hibiki] ✅ Chunk \(currentChunkIndex + 1) complete, chunk tokens: \(inputTokens), running total: \(totalInputTokens)")

            // Reset per-chunk state
            inputTokens = 0
            inputText = ""
            responseHeaders = [:]

            // Move to next chunk
            currentChunkIndex += 1
            processNextChunk()
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
