import Foundation

/// Result from the interleaved pipeline
struct InterleavedPipelineResult {
    let summarizedText: String
    let translatedText: String?
    let summarizationInputTokens: Int
    let summarizationOutputTokens: Int
    let translationInputTokens: Int
    let translationOutputTokens: Int
    let ttsInputTokens: Int
    let summarizationModel: String
    let translationModel: String?
}

/// Configuration for the interleaved pipeline
struct InterleavedPipelineConfig {
    let apiKey: String
    let summarizationModel: LLMModel
    let summarizationPrompt: String
    let targetLanguage: TargetLanguage
    let translationModel: LLMModel
    let translationPrompt: String
    let voice: TTSVoice
    let ttsInstructions: String
}

/// Error types for the interleaved pipeline
enum InterleavedPipelineError: Error, LocalizedError {
    case cancelled
    case summarizationFailed(Error)
    case translationFailed(Error)
    case ttsFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Pipeline was cancelled"
        case .summarizationFailed(let error):
            return "Summarization failed: \(error.localizedDescription)"
        case .translationFailed(let error):
            return "Translation failed: \(error.localizedDescription)"
        case .ttsFailed(let error):
            return "TTS failed: \(error.localizedDescription)"
        }
    }
}

/// Orchestrates interleaved summarization -> translation -> TTS pipeline
/// for reduced time-to-first-audio latency.
@MainActor
final class InterleavedPipeline {
    private let logger = DebugLogger.shared
    private let llmService = LLMService()
    private let ttsService = TTSService()

    // Make init nonisolated so it can be called from any context
    nonisolated init() {}

    private var isCancelled = false
    private var currentTask: Task<Void, Never>?
    private var runId: UUID = UUID()  // Unique ID for each pipeline run to detect stale callbacks

    // Accumulated results
    private var summarizedSentences: [String] = []
    private var translatedSentences: [String] = []
    private var summarizationInputTokens = 0
    private var summarizationOutputTokens = 0
    private var translationInputTokens = 0
    private var translationOutputTokens = 0
    private var ttsInputTokens = 0

    // Callbacks
    var onSummarySentence: ((String) -> Void)?
    var onTranslatedSentence: ((String) -> Void)?
    var onAudioChunk: ((Data) -> Void)?
    var onProgress: ((String) -> Void)?  // Status updates
    var onComplete: ((InterleavedPipelineResult) -> Void)?
    var onError: ((Error) -> Void)?

    // Sentence accumulator for detecting complete sentences
    private let sentenceAccumulator = SentenceAccumulator(minimumSentenceLength: 30)

    // Queue for serializing chunk processing to avoid race conditions
    private var pendingChunks: [String] = []
    private var isProcessingChunks = false
    private var chunkProcessingWaiters: [CheckedContinuation<Void, Never>] = []

    /// Minimum text length to use interleaved pipeline (shorter texts use sequential)
    private let minimumTextLength = 200

    /// Start the interleaved pipeline
    /// - Parameters:
    ///   - text: Input text to process
    ///   - config: Pipeline configuration
    @MainActor
    func start(text: String, config: InterleavedPipelineConfig) {
        logger.info("Starting interleaved pipeline for \(text.count) chars", source: "InterleavedPipeline")

        // Cancel any existing task to prevent stale results from previous runs
        if currentTask != nil {
            logger.info("Cancelling previous pipeline task before starting new one", source: "InterleavedPipeline")
            isCancelled = true
            currentTask?.cancel()
            currentTask = nil
            llmService.cancel()
            ttsService.cancel()
        }

        // Reset state
        isCancelled = false
        summarizedSentences = []
        translatedSentences = []
        summarizationInputTokens = 0
        summarizationOutputTokens = 0
        translationInputTokens = 0
        translationOutputTokens = 0
        ttsInputTokens = 0
        sentenceAccumulator.reset()
        pendingChunks = []
        isProcessingChunks = false

        // Generate new run ID to detect stale callbacks
        let thisRunId = UUID()
        runId = thisRunId
        logger.info("Starting pipeline run \(thisRunId)", source: "InterleavedPipeline")

        currentTask = Task {
            await runPipeline(text: text, config: config, runId: thisRunId)
        }
    }

    /// Cancel the pipeline (can be called from any context, dispatches to MainActor)
    nonisolated func cancel() {
        Task { @MainActor in
            self.logger.info("Cancelling interleaved pipeline", source: "InterleavedPipeline")
            self.isCancelled = true
            self.currentTask?.cancel()
            self.llmService.cancel()
            self.ttsService.cancel()
        }
    }

    /// Run the interleaved pipeline
    /// - Parameters:
    ///   - text: Input text to process
    ///   - config: Pipeline configuration
    ///   - runId: Unique ID for this run to detect stale callbacks
    private func runPipeline(text: String, config: InterleavedPipelineConfig, runId: UUID) async {
        do {
            // Start TTS pipeline session
            ttsService.startPipeline(
                voice: config.voice,
                apiKey: config.apiKey,
                instructions: config.ttsInstructions,
                onAudioChunk: { [weak self] data in
                    Task { @MainActor in
                        self?.onAudioChunk?(data)
                    }
                },
                onSentenceComplete: { [weak self] tokens in
                    self?.ttsInputTokens += tokens
                },
                onAllComplete: { [weak self] totalTokens in
                    self?.logger.debug("TTS pipeline complete: \(totalTokens) tokens", source: "InterleavedPipeline")
                },
                onError: { [weak self] error in
                    Task { @MainActor in
                        self?.handleError(InterleavedPipelineError.ttsFailed(error))
                    }
                }
            )

            // Stage 1: Streaming summarization with sentence extraction
            onProgress?("Summarizing...")
            logger.info("Starting summarization stage", source: "InterleavedPipeline")

            let llmResult = try await llmService.summarizeStreaming(
                text: text,
                model: config.summarizationModel,
                systemPrompt: config.summarizationPrompt,
                apiKey: config.apiKey,
                onChunk: { [weak self] chunk in
                    guard let self = self, !self.isCancelled else { return }
                    // Queue chunk for sequential processing
                    self.pendingChunks.append(chunk)
                    Task { @MainActor in
                        await self.processQueuedChunks(config: config)
                    }
                }
            )

            guard !isCancelled else {
                throw InterleavedPipelineError.cancelled
            }

            // Process any remaining queued chunks before flushing
            await processQueuedChunks(config: config)
            await waitForChunkProcessingToFinish()

            // Flush remaining summarization text
            if let remaining = sentenceAccumulator.flush() {
                await processSummarizedSentence(remaining, config: config)
            }

            summarizationInputTokens = llmResult.inputTokens
            summarizationOutputTokens = llmResult.outputTokens

            logger.info("Summarization complete: \(summarizedSentences.count) sentences, \(translatedSentences.count) translations", source: "InterleavedPipeline")

            // Log the actual contents of the arrays for debugging
            logger.debug("summarizedSentences contents: \(summarizedSentences)", source: "InterleavedPipeline")
            logger.debug("translatedSentences contents: \(translatedSentences)", source: "InterleavedPipeline")

            // Wait a moment for TTS queue to process remaining sentences
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s

            // Mark TTS as complete
            ttsService.markAllSentencesEnqueued()

            // Build final result
            let fullSummary = summarizedSentences.joined(separator: " ")
            let fullTranslation = config.targetLanguage != .none
                ? translatedSentences.joined(separator: " ")
                : nil

            logger.info("Building result - fullSummary length: \(fullSummary.count), fullTranslation length: \(fullTranslation?.count ?? 0)", source: "InterleavedPipeline")

            let result = InterleavedPipelineResult(
                summarizedText: fullSummary,
                translatedText: fullTranslation,
                summarizationInputTokens: summarizationInputTokens,
                summarizationOutputTokens: summarizationOutputTokens,
                translationInputTokens: translationInputTokens,
                translationOutputTokens: translationOutputTokens,
                ttsInputTokens: ttsInputTokens,
                summarizationModel: config.summarizationModel.rawValue,
                translationModel: config.targetLanguage != .none ? config.translationModel.rawValue : nil
            )

            // Check if this run is still current (not superseded by a new run)
            guard self.runId == runId else {
                logger.info("Pipeline run \(runId) superseded by new run \(self.runId), discarding result", source: "InterleavedPipeline")
                return
            }

            logger.info("Pipeline run \(runId) complete", source: "InterleavedPipeline")
            onComplete?(result)

        } catch {
            // Only report errors for the current run
            guard self.runId == runId else {
                logger.info("Pipeline run \(runId) error ignored (superseded by new run)", source: "InterleavedPipeline")
                return
            }
            if !isCancelled {
                handleError(error)
            }
        }
    }

    /// Process queued chunks sequentially to avoid race conditions
    @MainActor
    private func processQueuedChunks(config: InterleavedPipelineConfig) async {
        // Ensure only one processing task runs at a time
        guard !isProcessingChunks else {
            logger.debug("processQueuedChunks: already processing, returning (pendingChunks: \(pendingChunks.count))", source: "InterleavedPipeline")
            return
        }
        isProcessingChunks = true
        logger.debug("processQueuedChunks: starting processing (pendingChunks: \(pendingChunks.count))", source: "InterleavedPipeline")

        while !pendingChunks.isEmpty && !isCancelled {
            let chunk = pendingChunks.removeFirst()
            logger.debug("processQueuedChunks: processing chunk (\(chunk.count) chars), remaining: \(pendingChunks.count)", source: "InterleavedPipeline")

            // Accumulate and extract complete sentences
            let sentences = sentenceAccumulator.accumulate(chunk)
            logger.debug("processQueuedChunks: extracted \(sentences.count) sentences", source: "InterleavedPipeline")

            for sentence in sentences {
                await processSummarizedSentence(sentence, config: config)
            }
        }

        logger.debug("processQueuedChunks: finished (pendingChunks: \(pendingChunks.count), cancelled: \(isCancelled))", source: "InterleavedPipeline")
        finishChunkProcessing()
    }

    /// Process a complete summarized sentence through translation and TTS
    @MainActor
    private func processSummarizedSentence(_ sentence: String, config: InterleavedPipelineConfig) async {
        guard !isCancelled else { return }

        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        logger.debug("Processing summarized sentence: \(trimmed.prefix(50))...", source: "InterleavedPipeline")

        summarizedSentences.append(trimmed)
        onSummarySentence?(trimmed)

        // Stage 2: Translation (if needed)
        var textForTTS = trimmed

        if config.targetLanguage != .none {
            logger.debug("Starting translation for sentence \(summarizedSentences.count)", source: "InterleavedPipeline")
            do {
                onProgress?("Translating...")

                let translationResult = try await translateWithRetry(
                    sentence: trimmed,
                    context: translatedSentences.suffix(2).map { $0 },
                    config: config
                )
                let translated = translationResult.translatedText

                guard !isCancelled else {
                    logger.debug("Translation cancelled after completion for sentence \(summarizedSentences.count)", source: "InterleavedPipeline")
                    return
                }

                translatedSentences.append(translated)
                logger.info("Appended translation #\(translatedSentences.count): '\(translated.prefix(50))...' (total now: \(translatedSentences.count))", source: "InterleavedPipeline")
                onTranslatedSentence?(translated)
                textForTTS = translated
                logger.debug("Translation complete for sentence \(summarizedSentences.count): \(translated.prefix(50))...", source: "InterleavedPipeline")

                if translationResult.inputTokens > 0 {
                    translationInputTokens += translationResult.inputTokens
                } else {
                    translationInputTokens += max(1, trimmed.count / 4)
                }
                if translationResult.outputTokens > 0 {
                    translationOutputTokens += translationResult.outputTokens
                } else {
                    translationOutputTokens += max(1, translated.count / 4)
                }

            } catch {
                guard !isCancelled else {
                    logger.debug("Translation error but cancelled, skipping sentence \(summarizedSentences.count)", source: "InterleavedPipeline")
                    return
                }
                logger.error("Translation failed for sentence \(summarizedSentences.count): \(error.localizedDescription)", source: "InterleavedPipeline")
                handleError(InterleavedPipelineError.translationFailed(error))
                return
            }
        }

        // Stage 3: Queue for TTS
        guard !isCancelled else { return }
        onProgress?("Speaking...")
        ttsService.enqueueSentence(textForTTS)
    }

    /// Handle pipeline errors
    private func handleError(_ error: Error) {
        logger.error("Pipeline error: \(error.localizedDescription)", source: "InterleavedPipeline")
        isCancelled = true
        currentTask?.cancel()
        llmService.cancel()
        ttsService.cancel()
        onError?(error)
    }

    /// Wait for any in-flight chunk processing to complete.
    @MainActor
    private func waitForChunkProcessingToFinish() async {
        guard isProcessingChunks else { return }
        await withCheckedContinuation { continuation in
            chunkProcessingWaiters.append(continuation)
        }
    }

    /// Notify waiters that chunk processing has finished.
    @MainActor
    private func finishChunkProcessing() {
        isProcessingChunks = false
        guard !chunkProcessingWaiters.isEmpty else { return }
        let waiters = chunkProcessingWaiters
        chunkProcessingWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Retry translation a few times to handle transient errors (rate limits, timeouts)
    @MainActor
    private func translateWithRetry(
        sentence: String,
        context: [String],
        config: InterleavedPipelineConfig,
        maxAttempts: Int = 3
    ) async throws -> TranslationResult {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            guard !isCancelled else {
                throw InterleavedPipelineError.cancelled
            }
            do {
                return try await llmService.translateStreaming(
                    text: sentence,
                    context: context,
                    targetLanguage: config.targetLanguage,
                    model: config.translationModel,
                    systemPrompt: config.translationPrompt,
                    apiKey: config.apiKey,
                    onChunk: { _ in }
                )
            } catch {
                lastError = error
                let attemptNumber = attempt + 1
                if attemptNumber < maxAttempts {
                    logger.warning("Translation attempt \(attemptNumber) failed, retrying...", source: "InterleavedPipeline")
                    let backoffNs: UInt64 = 300_000_000 * UInt64(1 << attempt) // 0.3s, 0.6s, 1.2s
                    try? await Task.sleep(nanoseconds: backoffNs)
                }
            }
        }
        throw lastError ?? InterleavedPipelineError.translationFailed(LLMError.emptyResponse)
    }
}
