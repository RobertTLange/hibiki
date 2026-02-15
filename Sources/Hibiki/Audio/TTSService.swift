import Foundation

enum TTSVoice: String, CaseIterable, Identifiable {
    case alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse
    var id: String { rawValue }
}

enum TTSProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case elevenLabs = "elevenlabs"
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .elevenLabs: return "ElevenLabs"
        }
    }
}

enum ElevenLabsModel: String, CaseIterable, Identifiable {
    case elevenV3 = "eleven_v3"
    case elevenMultilingualV2 = "eleven_multilingual_v2"
    case elevenFlashV25 = "eleven_flash_v2_5"
    case elevenTurboV25 = "eleven_turbo_v2_5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenV3: return "Eleven v3"
        case .elevenMultilingualV2: return "Eleven Multilingual v2"
        case .elevenFlashV25: return "Eleven Flash v2.5"
        case .elevenTurboV25: return "Eleven Turbo v2.5"
        }
    }
}

struct TTSConfiguration {
    static let defaultInstructions = "Speak naturally and clearly."
    static let defaultElevenLabsModelID = ElevenLabsModel.elevenFlashV25.rawValue

    let provider: TTSProvider
    let openAIAPIKey: String
    let openAIVoice: TTSVoice
    let elevenLabsAPIKey: String
    let elevenLabsVoiceID: String
    let elevenLabsModelID: String
    let instructions: String

    var historyVoiceLabel: String {
        switch provider {
        case .openAI:
            return openAIVoice.rawValue
        case .elevenLabs:
            return "elevenlabs:\(elevenLabsVoiceID)"
        }
    }

    var normalizedElevenLabsModelID: String {
        let trimmed = elevenLabsModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.defaultElevenLabsModelID }
        return ElevenLabsModel(rawValue: trimmed)?.rawValue ?? Self.defaultElevenLabsModelID
    }
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
    private var currentConfiguration: TTSConfiguration?

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
        configuration: TTSConfiguration,
        onAudioChunk: @escaping (Data) -> Void,
        onComplete: @escaping (TTSResult) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        print("[Hibiki] TTSService.streamSpeech called")
        print("[Hibiki] Text length: \(text.count), provider: \(configuration.provider.rawValue)")

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

        switch configuration.provider {
        case .openAI:
            guard !configuration.openAIAPIKey.isEmpty else {
                print("[Hibiki] ❌ OpenAI API key is empty in TTSService")
                onError(TTSError.missingAPIKey(provider: .openAI))
                return
            }
        case .elevenLabs:
            guard !configuration.elevenLabsAPIKey.isEmpty else {
                print("[Hibiki] ❌ ElevenLabs API key is empty in TTSService")
                onError(TTSError.missingAPIKey(provider: .elevenLabs))
                return
            }
            guard !configuration.elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[Hibiki] ❌ ElevenLabs voice ID is empty in TTSService")
                onError(TTSError.missingVoiceID(provider: .elevenLabs))
                return
            }
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
        currentConfiguration = configuration

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

        guard let configuration = currentConfiguration else {
            print("[Hibiki] ❌ Missing TTS configuration")
            onError?(TTSError.invalidConfiguration)
            return
        }

        switch configuration.provider {
        case .openAI:
            streamSingleChunkWithOpenAI(text: text, configuration: configuration)
        case .elevenLabs:
            streamSingleChunkWithElevenLabs(text: text, configuration: configuration)
        }
    }

    private func streamSingleChunkWithOpenAI(text: String, configuration: TTSConfiguration) {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("[Hibiki] ❌ Invalid URL")
            onError?(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": configuration.openAIVoice.rawValue,
            "instructions": configuration.instructions,
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

    private func streamSingleChunkWithElevenLabs(
        text: String,
        configuration: TTSConfiguration,
        allowModelFallback: Bool = true
    ) {
        let voiceID = configuration.elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let encodedVoiceID = voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoiceID)/stream"),
              let url = {
                  components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
                  return components.url
              }() else {
            print("[Hibiki] ❌ Invalid ElevenLabs URL")
            onError?(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/pcm", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": configuration.normalizedElevenLabsModelID
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Hibiki] ❌ JSON encoding error: \(error)")
            onError?(error)
            return
        }

        print("[Hibiki] 🌐 Making API request to ElevenLabs for chunk \(currentChunkIndex + 1)...")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if self.isCancelled {
                return
            }

            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("[Hibiki] ❌ ElevenLabs network error: \(error.localizedDescription)")
                    self.onError?(error)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.onError?(TTSError.apiError(statusCode: 0, message: nil))
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("[Hibiki] ❌ ElevenLabs API error: HTTP \(httpResponse.statusCode)")
                var parsedErrorMessage: String?
                if let errorBody = data,
                   let parsed = self.parseErrorMessage(from: errorBody) {
                    print("[Hibiki] ❌ ElevenLabs error body: \(parsed)")
                    parsedErrorMessage = parsed
                }

                if allowModelFallback,
                   let fallbackModelID = self.fallbackElevenLabsModelID(
                    statusCode: httpResponse.statusCode,
                    currentModelID: configuration.normalizedElevenLabsModelID,
                    errorMessage: parsedErrorMessage
                   ) {
                    print("[Hibiki] 🔁 Retrying ElevenLabs chunk with fallback model: \(fallbackModelID)")
                    let fallbackConfiguration = self.configurationByUpdatingElevenLabsModel(configuration, modelID: fallbackModelID)
                    self.currentConfiguration = fallbackConfiguration
                    self.streamSingleChunkWithElevenLabs(
                        text: text,
                        configuration: fallbackConfiguration,
                        allowModelFallback: false
                    )
                    return
                }

                self.onError?(TTSError.apiError(statusCode: httpResponse.statusCode, message: parsedErrorMessage))
                return
            }

            guard let audioData = data, !audioData.isEmpty else {
                print("[Hibiki] ⚠️ ElevenLabs returned empty audio data")
                self.onError?(TTSError.emptyAudioData)
                return
            }

            self.receivedChunkCount += 1
            self.receivedChunkBytes += audioData.count
            self.accumulatedAudioData.append(audioData)
            self.onAudioChunk?(audioData)

            let estimatedTokens = max(1, text.count / 4)
            self.isTokenEstimated = true
            self.totalInputTokens += estimatedTokens

            print("[Hibiki] ✅ Chunk \(self.currentChunkIndex + 1) complete, estimated tokens: \(estimatedTokens), running total: \(self.totalInputTokens)")

            self.currentChunkIndex += 1
            self.processNextChunk()
        }

        currentTask = task
        task.resume()
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
        configuration: TTSConfiguration,
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
        currentConfiguration = configuration
        pipelineOnAudioChunk = onAudioChunk
        pipelineOnSentenceComplete = onSentenceComplete
        pipelineOnAllComplete = onAllComplete
        pipelineOnError = onError
        accumulatedAudioData = Data()

        switch configuration.provider {
        case .openAI:
            guard !configuration.openAIAPIKey.isEmpty else {
                print("[Hibiki] ❌ OpenAI API key is empty in TTSService pipeline")
                onError(TTSError.missingAPIKey(provider: .openAI))
                return
            }
        case .elevenLabs:
            guard !configuration.elevenLabsAPIKey.isEmpty else {
                print("[Hibiki] ❌ ElevenLabs API key is empty in TTSService pipeline")
                onError(TTSError.missingAPIKey(provider: .elevenLabs))
                return
            }
            guard !configuration.elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[Hibiki] ❌ ElevenLabs voice ID is empty in TTSService pipeline")
                onError(TTSError.missingVoiceID(provider: .elevenLabs))
                return
            }
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

        guard let configuration = currentConfiguration else {
            pipelineOnError?(TTSError.invalidConfiguration)
            return
        }

        switch configuration.provider {
        case .openAI:
            streamPipelineSentenceWithOpenAI(text: text, configuration: configuration)
        case .elevenLabs:
            streamPipelineSentenceWithElevenLabs(text: text, configuration: configuration)
        }
    }

    private func streamPipelineSentenceWithOpenAI(text: String, configuration: TTSConfiguration) {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("[Hibiki] ❌ Invalid URL")
            pipelineOnError?(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": configuration.openAIVoice.rawValue,
            "instructions": configuration.instructions,
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
                self.pipelineOnError?(TTSError.apiError(statusCode: 0, message: nil))
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("[Hibiki] ❌ Pipeline TTS API error: HTTP \(httpResponse.statusCode)")
                self.pipelineOnError?(TTSError.apiError(statusCode: httpResponse.statusCode, message: nil))
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

    private func streamPipelineSentenceWithElevenLabs(
        text: String,
        configuration: TTSConfiguration,
        allowModelFallback: Bool = true
    ) {
        let voiceID = configuration.elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let encodedVoiceID = voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoiceID)/stream"),
              let url = {
                  components.queryItems = [URLQueryItem(name: "output_format", value: "pcm_24000")]
                  return components.url
              }() else {
            print("[Hibiki] ❌ Invalid ElevenLabs URL")
            pipelineOnError?(TTSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/pcm", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": configuration.normalizedElevenLabsModelID
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Hibiki] ❌ JSON encoding error: \(error)")
            pipelineOnError?(error)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if self.isCancelled {
                return
            }

            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("[Hibiki] ❌ Pipeline ElevenLabs error: \(error.localizedDescription)")
                    self.pipelineOnError?(error)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.pipelineOnError?(TTSError.apiError(statusCode: 0, message: nil))
                return
            }

            guard httpResponse.statusCode == 200 else {
                print("[Hibiki] ❌ Pipeline ElevenLabs API error: HTTP \(httpResponse.statusCode)")
                var parsedErrorMessage: String?
                if let errorBody = data,
                   let parsed = self.parseErrorMessage(from: errorBody) {
                    print("[Hibiki] ❌ Pipeline ElevenLabs error body: \(parsed)")
                    parsedErrorMessage = parsed
                }

                if allowModelFallback,
                   let fallbackModelID = self.fallbackElevenLabsModelID(
                    statusCode: httpResponse.statusCode,
                    currentModelID: configuration.normalizedElevenLabsModelID,
                    errorMessage: parsedErrorMessage
                   ) {
                    print("[Hibiki] 🔁 Retrying ElevenLabs pipeline sentence with fallback model: \(fallbackModelID)")
                    let fallbackConfiguration = self.configurationByUpdatingElevenLabsModel(configuration, modelID: fallbackModelID)
                    self.currentConfiguration = fallbackConfiguration
                    self.streamPipelineSentenceWithElevenLabs(
                        text: text,
                        configuration: fallbackConfiguration,
                        allowModelFallback: false
                    )
                    return
                }

                self.pipelineOnError?(TTSError.apiError(statusCode: httpResponse.statusCode, message: parsedErrorMessage))
                return
            }

            guard let audioData = data, !audioData.isEmpty else {
                print("[Hibiki] ⚠️ Pipeline ElevenLabs returned empty data")
                self.finishCurrentSentence(tokens: 0)
                return
            }

            let estimatedTokens = max(1, text.count / 4)

            print("[Hibiki] ✅ Pipeline sentence complete: \(audioData.count) bytes, ~\(estimatedTokens) tokens")

            self.pipelineOnAudioChunk?(audioData)
            self.finishCurrentSentence(tokens: estimatedTokens)
        }

        task.resume()
    }

    private func configurationByUpdatingElevenLabsModel(
        _ configuration: TTSConfiguration,
        modelID: String
    ) -> TTSConfiguration {
        TTSConfiguration(
            provider: configuration.provider,
            openAIAPIKey: configuration.openAIAPIKey,
            openAIVoice: configuration.openAIVoice,
            elevenLabsAPIKey: configuration.elevenLabsAPIKey,
            elevenLabsVoiceID: configuration.elevenLabsVoiceID,
            elevenLabsModelID: modelID,
            instructions: configuration.instructions
        )
    }

    private func fallbackElevenLabsModelID(
        statusCode: Int,
        currentModelID: String,
        errorMessage: String?
    ) -> String? {
        guard statusCode == 402 || statusCode == 403 else {
            return nil
        }

        let normalizedCurrent = ElevenLabsModel(rawValue: currentModelID)?.rawValue ?? currentModelID
        let fallback = ElevenLabsModel.elevenMultilingualV2.rawValue
        guard normalizedCurrent != fallback else {
            return nil
        }

        if let message = errorMessage?.lowercased(),
           (message.contains("credit") || message.contains("quota")) {
            return nil
        }

        return fallback
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? [String: Any] {
                if let message = detail["message"] as? String {
                    return message
                }
                if let status = detail["status"] as? String {
                    return status
                }
            }
            if let message = json["message"] as? String {
                return message
            }
            return String(describing: json)
        }
        return String(data: data, encoding: .utf8)
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
                onError?(TTSError.apiError(statusCode: httpResponse.statusCode, message: nil))
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
    case missingAPIKey(provider: TTSProvider)
    case missingVoiceID(provider: TTSProvider)
    case invalidConfiguration
    case invalidURL
    case apiError(statusCode: Int, message: String?)
    case emptyAudioData

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            switch provider {
            case .openAI:
                return "OpenAI API key is not configured"
            case .elevenLabs:
                return "ElevenLabs API key is not configured"
            }
        case .missingVoiceID(let provider):
            switch provider {
            case .openAI:
                return "OpenAI voice is not configured"
            case .elevenLabs:
                return "ElevenLabs voice ID is not configured"
            }
        case .invalidConfiguration:
            return "Invalid TTS configuration"
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "API error: HTTP \(statusCode) (\(message))"
            }
            return "API error: HTTP \(statusCode)"
        case .emptyAudioData:
            return "TTS API returned empty audio data"
        }
    }
}
