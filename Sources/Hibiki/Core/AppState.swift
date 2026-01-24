import SwiftUI
import KeyboardShortcuts

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var isSummarizing = false
    @Published var isTranslating = false
    @Published var currentText: String?
    @Published var errorMessage: String?
    @Published var streamingSummary: String = ""  // Accumulates streaming summary text
    @Published var streamingTranslation: String = ""  // Accumulates streaming translation text

    // Text highlighting during playback
    @Published var playbackProgress: Double = 0.0
    @Published var highlightCharacterIndex: Int = 0
    @Published var displayText: String = ""  // Text being spoken (raw/summarized/translated)

    @AppStorage("selectedVoice") var selectedVoice: String = TTSVoice.coral.rawValue
    @AppStorage("openaiAPIKey") var apiKey: String = ""
    @AppStorage("playbackSpeed") var playbackSpeed: Double = 1.0

    // Summarization settings
    @AppStorage("summarizationModel") var summarizationModel: String = LLMModel.gpt5Nano.rawValue
    @AppStorage("summarizationPrompt") var summarizationPrompt: String = """
        Summarize the following text concisely while preserving the key information. \
        The summary should be suitable for text-to-speech, so write in complete sentences \
        and avoid bullet points or special formatting. Keep it under 3 paragraphs.
        """

    // Translation settings
    @AppStorage("targetLanguage") var targetLanguage: String = TargetLanguage.none.rawValue
    @AppStorage("translationModel") var translationModelSetting: String = LLMModel.gpt5Nano.rawValue
    
    // Per-language translation prompts (stored separately for each language)
    @AppStorage("translationPrompt_en") var translationPromptEnglish: String = TargetLanguage.english.defaultPrompt
    @AppStorage("translationPrompt_fr") var translationPromptFrench: String = TargetLanguage.french.defaultPrompt
    @AppStorage("translationPrompt_de") var translationPromptGerman: String = TargetLanguage.german.defaultPrompt
    @AppStorage("translationPrompt_ja") var translationPromptJapanese: String = TargetLanguage.japanese.defaultPrompt
    @AppStorage("translationPrompt_es") var translationPromptSpanish: String = TargetLanguage.spanish.defaultPrompt

    /// Get the translation prompt for the currently selected language
    var currentTranslationPrompt: String {
        get {
            guard let language = TargetLanguage(rawValue: targetLanguage) else { return "" }
            switch language {
            case .none: return ""
            case .english: return translationPromptEnglish
            case .french: return translationPromptFrench
            case .german: return translationPromptGerman
            case .japanese: return translationPromptJapanese
            case .spanish: return translationPromptSpanish
            }
        }
        set {
            guard let language = TargetLanguage(rawValue: targetLanguage) else { return }
            switch language {
            case .none: break
            case .english: translationPromptEnglish = newValue
            case .french: translationPromptFrench = newValue
            case .german: translationPromptGerman = newValue
            case .japanese: translationPromptJapanese = newValue
            case .spanish: translationPromptSpanish = newValue
            }
        }
    }

    /// Get translation prompt for a specific language
    func translationPrompt(for language: TargetLanguage) -> String {
        switch language {
        case .none: return ""
        case .english: return translationPromptEnglish
        case .french: return translationPromptFrench
        case .german: return translationPromptGerman
        case .japanese: return translationPromptJapanese
        case .spanish: return translationPromptSpanish
        }
    }

    // Audio level monitor for waveform visualization
    let audioLevelMonitor = AudioLevelMonitor()

    private let ttsService = TTSService()
    private let llmService = LLMService()
    private let audioPlayer = StreamingAudioPlayer.shared
    private let accessibilityManager = AccessibilityManager.shared
    private var summarizationTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    private let logger = DebugLogger.shared
    private var progressTimer: Timer?
    private var lastHighlightIndex: Int = 0  // For smoothing highlight movement

    // Track state for history save on stop
    private var accumulatedAudioData = Data()
    private var pendingHistorySave: (
        text: String,
        voice: String,
        inputTokens: Int,
        summarizedText: String?,
        llmInputTokens: Int?,
        llmOutputTokens: Int?,
        llmModel: String?,
        translatedText: String?,
        translationInputTokens: Int?,
        translationOutputTokens: Int?,
        translationModel: String?,
        targetLanguage: String?
    )?
    private var historySaved = false

    init() {
        // Default API key from environment variable if not set
        if apiKey.isEmpty, let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            apiKey = envKey
            logger.info("Loaded API key from environment variable", source: "AppState")
        }
        setupHotkeyHandler()
        logger.info("AppState initialized, hotkey handler registered", source: "AppState")
    }

    private func setupHotkeyHandler() {
        logger.debug("Setting up hotkey handler for .triggerTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerTTS) { [weak self] in
            self?.logger.info("Hotkey pressed!", source: "AppState")
            Task { @MainActor in
                await self?.handleHotkeyPressed()
            }
        }

        logger.debug("Setting up hotkey handler for .triggerSummarizeTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerSummarizeTTS) { [weak self] in
            self?.logger.info("Summarize+TTS hotkey pressed!", source: "AppState")
            self?.summarizationTask?.cancel()
            self?.summarizationTask = Task { @MainActor in
                await self?.handleSummarizeTTSPressed()
            }
        }

        logger.debug("Setting up hotkey handler for .triggerTranslateTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerTranslateTTS) { [weak self] in
            self?.logger.info("Translate+TTS hotkey pressed!", source: "AppState")
            self?.translationTask?.cancel()
            self?.translationTask = Task { @MainActor in
                await self?.handleTranslateTTSPressed()
            }
        }

        logger.debug("Setting up hotkey handler for .triggerSummarizeTranslateTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerSummarizeTranslateTTS) { [weak self] in
            self?.logger.info("Summarize+Translate+TTS hotkey pressed!", source: "AppState")
            self?.summarizationTask?.cancel()
            self?.translationTask?.cancel()
            self?.summarizationTask = Task { @MainActor in
                await self?.handleSummarizeTranslateTTSPressed()
            }
        }
    }

    @MainActor
    func handleHotkeyPressed() async {
        logger.debug("handleHotkeyPressed called", source: "AppState")

        // If already playing, stop
        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        do {
            isLoading = true
            errorMessage = nil

            // Get selected text
            logger.debug("Attempting to get selected text...", source: "AppState")
            let text = try accessibilityManager.getSelectedText()
            logger.debug("Got text: \(text ?? "nil")", source: "AppState")

            guard let text = text, !text.isEmpty else {
                logger.error("No text selected", source: "AppState")
                errorMessage = "No text selected"
                isLoading = false
                return
            }

            logger.info("Selected text (\(text.count) chars): \"\(text)\"", source: "AppState")

            // Check API key - try environment variable again if empty
            var effectiveApiKey = apiKey
            if effectiveApiKey.isEmpty {
                if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
                    effectiveApiKey = envKey
                    apiKey = envKey  // Save it for future use
                    logger.info("Loaded API key from environment variable", source: "AppState")
                } else {
                    logger.error("API key is empty!", source: "AppState")
                    errorMessage = "No API key configured. Enter key in Settings."
                    isLoading = false
                    return
                }
            }
            logger.info("API key present (\(effectiveApiKey.prefix(8))...)", source: "AppState")

            currentText = text
            isPlaying = true
            isLoading = false

            // Reset tracking state
            accumulatedAudioData = Data()
            pendingHistorySave = nil
            historySaved = false

            // Set display text for highlighting (raw text for direct TTS)
            displayText = text

            // Reset audio player for fresh playback (must be before setEstimatedDuration)
            audioPlayer.reset()
            audioPlayer.playbackSpeed = Float(playbackSpeed)
            audioPlayer.setEstimatedDuration(forTextLength: text.count)
            startProgressTracking()

            // Get the voice enum from stored string
            let voice = TTSVoice(rawValue: selectedVoice) ?? .coral
            logger.info("Using voice: \(voice.rawValue)", source: "AppState")

            // Store pending history info for save on stop (no summarization for direct TTS)
            pendingHistorySave = (
                text: text,
                voice: voice.rawValue,
                inputTokens: 0,
                summarizedText: nil,
                llmInputTokens: nil,
                llmOutputTokens: nil,
                llmModel: nil,
                translatedText: nil,
                translationInputTokens: nil,
                translationOutputTokens: nil,
                translationModel: nil,
                targetLanguage: nil
            )

            // Set up playback completion callback
            audioPlayer.onPlaybackComplete = { [weak self] in
                self?.logger.info("Audio playback complete", source: "AppState")
                Task { @MainActor in
                    self?.handlePlaybackComplete()
                }
            }

            // Start audio level monitoring
            audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)

            // Start streaming TTS
            logger.info("Starting TTS stream...", source: "AppState")
            ttsService.streamSpeech(
                text: text,
                voice: voice,
                apiKey: effectiveApiKey,
                onAudioChunk: { [weak self] data in
                    self?.logger.debug("Received audio chunk: \(data.count) bytes", source: "AppState")
                    self?.audioPlayer.enqueue(pcmData: data)
                    self?.accumulatedAudioData.append(data)
                },
                onComplete: { [weak self] result in
                    self?.logger.info("TTS stream complete, audio size: \(result.audioData.count) bytes, inputTokens: \(result.inputTokens)", source: "AppState")

                    // Update pending history with actual token count
                    if var pending = self?.pendingHistorySave {
                        pending.inputTokens = result.inputTokens
                        self?.pendingHistorySave = pending
                    }

                    // Mark stream as complete so player can detect when audio finishes
                    self?.audioPlayer.markStreamComplete()
                },
                onError: { [weak self] error in
                    self?.logger.error("TTS error: \(error.localizedDescription)", source: "AppState")
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                        self?.isPlaying = false
                        self?.audioLevelMonitor.stopMonitoring()
                    }
                }
            )
        } catch {
            logger.error("Exception: \(error.localizedDescription)", source: "AppState")
            errorMessage = error.localizedDescription
            isLoading = false
            isPlaying = false
        }
    }

    @MainActor
    func handleSummarizeTTSPressed() async {
        logger.debug("handleSummarizeTTSPressed called", source: "AppState")

        // If already playing, stop
        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        do {
            isLoading = true
            isSummarizing = true
            errorMessage = nil

            // Get selected text
            logger.debug("Attempting to get selected text for summarization...", source: "AppState")
            let text = try accessibilityManager.getSelectedText()
            logger.debug("Got text: \(text ?? "nil")", source: "AppState")

            guard let text = text, !text.isEmpty else {
                logger.error("No text selected", source: "AppState")
                errorMessage = "No text selected"
                isLoading = false
                isSummarizing = false
                return
            }

            logger.info("Selected text for summarization (\(text.count) chars)", source: "AppState")

            // Check API key
            var effectiveApiKey = apiKey
            if effectiveApiKey.isEmpty {
                if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
                    effectiveApiKey = envKey
                    apiKey = envKey
                    logger.info("Loaded API key from environment variable", source: "AppState")
                } else {
                    logger.error("API key is empty!", source: "AppState")
                    errorMessage = "No API key configured. Enter key in Settings."
                    isLoading = false
                    isSummarizing = false
                    return
                }
            }

            // Summarize text with streaming
            let model = LLMModel(rawValue: summarizationModel) ?? .gpt5Nano
            logger.info("Summarizing with model: \(model.rawValue)", source: "AppState")
            
            // Reset streaming summary
            streamingSummary = ""

            let llmResult = try await llmService.summarizeStreaming(
                text: text,
                model: model,
                systemPrompt: summarizationPrompt,
                apiKey: effectiveApiKey,
                onChunk: { [weak self] chunk in
                    guard let self = self else { return }
                    self.logger.debug("LLM chunk received: \(chunk.count) chars", source: "AppState")
                    self.streamingSummary += chunk
                }
            )

            logger.info("Summarization complete: \(llmResult.summarizedText.count) chars, \(llmResult.inputTokens) input tokens, \(llmResult.outputTokens) output tokens", source: "AppState")

            isSummarizing = false

            // Now proceed with TTS using summarized text
            currentText = llmResult.summarizedText
            isPlaying = true
            isLoading = false

            // Reset tracking state
            accumulatedAudioData = Data()
            pendingHistorySave = nil
            historySaved = false

            // Set display text for highlighting (summarized text)
            displayText = llmResult.summarizedText

            // Reset audio player for fresh playback (must be before setEstimatedDuration)
            audioPlayer.reset()
            audioPlayer.playbackSpeed = Float(playbackSpeed)
            audioPlayer.setEstimatedDuration(forTextLength: llmResult.summarizedText.count)
            startProgressTracking()

            let voice = TTSVoice(rawValue: selectedVoice) ?? .coral
            logger.info("Using voice: \(voice.rawValue)", source: "AppState")

            // Store pending history with summarization metadata
            pendingHistorySave = (
                text: text,  // Original text
                voice: voice.rawValue,
                inputTokens: 0,
                summarizedText: llmResult.summarizedText,
                llmInputTokens: llmResult.inputTokens,
                llmOutputTokens: llmResult.outputTokens,
                llmModel: llmResult.model,
                translatedText: nil,
                translationInputTokens: nil,
                translationOutputTokens: nil,
                translationModel: nil,
                targetLanguage: nil
            )

            audioPlayer.onPlaybackComplete = { [weak self] in
                self?.logger.info("Audio playback complete", source: "AppState")
                Task { @MainActor in
                    self?.handlePlaybackComplete()
                }
            }

            audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)

            // TTS the summarized text
            logger.info("Starting TTS stream for summarized text...", source: "AppState")
            ttsService.streamSpeech(
                text: llmResult.summarizedText,
                voice: voice,
                apiKey: effectiveApiKey,
                onAudioChunk: { [weak self] data in
                    self?.logger.debug("Received audio chunk: \(data.count) bytes", source: "AppState")
                    self?.audioPlayer.enqueue(pcmData: data)
                    self?.accumulatedAudioData.append(data)
                },
                onComplete: { [weak self] result in
                    self?.logger.info("TTS stream complete, audio size: \(result.audioData.count) bytes, inputTokens: \(result.inputTokens)", source: "AppState")

                    // Update pending history with actual TTS token count
                    if var pending = self?.pendingHistorySave {
                        pending.inputTokens = result.inputTokens
                        self?.pendingHistorySave = pending
                    }

                    self?.audioPlayer.markStreamComplete()
                },
                onError: { [weak self] error in
                    self?.logger.error("TTS error: \(error.localizedDescription)", source: "AppState")
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                        self?.isPlaying = false
                        self?.isSummarizing = false
                        self?.audioLevelMonitor.stopMonitoring()
                    }
                }
            )
        } catch {
            logger.error("Summarize+TTS exception: \(error.localizedDescription)", source: "AppState")
            errorMessage = error.localizedDescription
            isLoading = false
            isPlaying = false
            isSummarizing = false
        }
    }

    @MainActor
    func handleTranslateTTSPressed() async {
        logger.debug("handleTranslateTTSPressed called", source: "AppState")

        // If already playing, stop
        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        do {
            isLoading = true
            errorMessage = nil

            // Get selected text
            logger.debug("Attempting to get selected text for translation...", source: "AppState")
            let text = try accessibilityManager.getSelectedText()
            logger.debug("Got text: \(text ?? "nil")", source: "AppState")

            guard let text = text, !text.isEmpty else {
                logger.error("No text selected", source: "AppState")
                errorMessage = "No text selected"
                isLoading = false
                return
            }

            logger.info("Selected text for translation (\(text.count) chars)", source: "AppState")

            // Check API key
            var effectiveApiKey = apiKey
            if effectiveApiKey.isEmpty {
                if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
                    effectiveApiKey = envKey
                    apiKey = envKey
                    logger.info("Loaded API key from environment variable", source: "AppState")
                } else {
                    logger.error("API key is empty!", source: "AppState")
                    errorMessage = "No API key configured. Enter key in Settings."
                    isLoading = false
                    return
                }
            }

            let language = TargetLanguage(rawValue: targetLanguage) ?? .none
            var textForTTS = text
            var translationResult: TranslationResult? = nil

            // Translate if target language is set
            if language != .none {
                isTranslating = true
                let translationModel = LLMModel(rawValue: translationModelSetting) ?? .gpt5Nano
                logger.info("Translating to \(language.languageName) with model: \(translationModel.rawValue)", source: "AppState")

                streamingTranslation = ""

                translationResult = try await llmService.translateStreaming(
                    text: text,
                    targetLanguage: language,
                    model: translationModel,
                    systemPrompt: translationPrompt(for: language),
                    apiKey: effectiveApiKey,
                    onChunk: { [weak self] chunk in
                        guard let self = self else { return }
                        self.logger.debug("Translation chunk received: \(chunk.count) chars", source: "AppState")
                        self.streamingTranslation += chunk
                    }
                )

                logger.info("Translation complete: \(translationResult!.translatedText.count) chars", source: "AppState")
                textForTTS = translationResult!.translatedText
                isTranslating = false
            }

            // Now proceed with TTS
            currentText = textForTTS
            isPlaying = true
            isLoading = false

            // Reset tracking state
            accumulatedAudioData = Data()
            pendingHistorySave = nil
            historySaved = false

            // Set display text for highlighting (translated text or original if no translation)
            displayText = textForTTS

            // Reset audio player for fresh playback (must be before setEstimatedDuration)
            audioPlayer.reset()
            audioPlayer.playbackSpeed = Float(playbackSpeed)
            audioPlayer.setEstimatedDuration(forTextLength: textForTTS.count)
            startProgressTracking()

            let voice = TTSVoice(rawValue: selectedVoice) ?? .coral
            logger.info("Using voice: \(voice.rawValue)", source: "AppState")

            // Store pending history with translation metadata
            pendingHistorySave = (
                text: text,  // Original text
                voice: voice.rawValue,
                inputTokens: 0,
                summarizedText: nil,
                llmInputTokens: nil,
                llmOutputTokens: nil,
                llmModel: nil,
                translatedText: translationResult?.translatedText,
                translationInputTokens: translationResult?.inputTokens,
                translationOutputTokens: translationResult?.outputTokens,
                translationModel: translationResult?.model,
                targetLanguage: language != .none ? language.rawValue : nil
            )

            audioPlayer.onPlaybackComplete = { [weak self] in
                self?.logger.info("Audio playback complete", source: "AppState")
                Task { @MainActor in
                    self?.handlePlaybackComplete()
                }
            }

            audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)

            // TTS the translated text
            logger.info("Starting TTS stream for translated text...", source: "AppState")
            ttsService.streamSpeech(
                text: textForTTS,
                voice: voice,
                apiKey: effectiveApiKey,
                onAudioChunk: { [weak self] data in
                    self?.logger.debug("Received audio chunk: \(data.count) bytes", source: "AppState")
                    self?.audioPlayer.enqueue(pcmData: data)
                    self?.accumulatedAudioData.append(data)
                },
                onComplete: { [weak self] result in
                    self?.logger.info("TTS stream complete, audio size: \(result.audioData.count) bytes, inputTokens: \(result.inputTokens)", source: "AppState")

                    if var pending = self?.pendingHistorySave {
                        pending.inputTokens = result.inputTokens
                        self?.pendingHistorySave = pending
                    }

                    self?.audioPlayer.markStreamComplete()
                },
                onError: { [weak self] error in
                    self?.logger.error("TTS error: \(error.localizedDescription)", source: "AppState")
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                        self?.isPlaying = false
                        self?.isTranslating = false
                        self?.audioLevelMonitor.stopMonitoring()
                    }
                }
            )
        } catch {
            logger.error("Translate+TTS exception: \(error.localizedDescription)", source: "AppState")
            errorMessage = error.localizedDescription
            isLoading = false
            isPlaying = false
            isTranslating = false
        }
    }

    @MainActor
    func handleSummarizeTranslateTTSPressed() async {
        logger.debug("handleSummarizeTranslateTTSPressed called", source: "AppState")

        // If already playing, stop
        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        do {
            isLoading = true
            isSummarizing = true
            errorMessage = nil

            // Get selected text
            logger.debug("Attempting to get selected text for summarize+translate...", source: "AppState")
            let text = try accessibilityManager.getSelectedText()
            logger.debug("Got text: \(text ?? "nil")", source: "AppState")

            guard let text = text, !text.isEmpty else {
                logger.error("No text selected", source: "AppState")
                errorMessage = "No text selected"
                isLoading = false
                isSummarizing = false
                return
            }

            logger.info("Selected text for summarize+translate (\(text.count) chars)", source: "AppState")

            // Check API key
            var effectiveApiKey = apiKey
            if effectiveApiKey.isEmpty {
                if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
                    effectiveApiKey = envKey
                    apiKey = envKey
                    logger.info("Loaded API key from environment variable", source: "AppState")
                } else {
                    logger.error("API key is empty!", source: "AppState")
                    errorMessage = "No API key configured. Enter key in Settings."
                    isLoading = false
                    isSummarizing = false
                    return
                }
            }

            // Summarize text with streaming
            let model = LLMModel(rawValue: summarizationModel) ?? .gpt5Nano
            logger.info("Summarizing with model: \(model.rawValue)", source: "AppState")

            streamingSummary = ""

            let llmResult = try await llmService.summarizeStreaming(
                text: text,
                model: model,
                systemPrompt: summarizationPrompt,
                apiKey: effectiveApiKey,
                onChunk: { [weak self] chunk in
                    guard let self = self else { return }
                    self.logger.debug("LLM chunk received: \(chunk.count) chars", source: "AppState")
                    self.streamingSummary += chunk
                }
            )

            logger.info("Summarization complete: \(llmResult.summarizedText.count) chars", source: "AppState")
            isSummarizing = false

            // Now translate if target language is set
            let language = TargetLanguage(rawValue: targetLanguage) ?? .none
            var textForTTS = llmResult.summarizedText
            var translationResult: TranslationResult? = nil

            if language != .none {
                isTranslating = true
                let translationModel = LLMModel(rawValue: translationModelSetting) ?? .gpt5Nano
                logger.info("Translating summarized text to \(language.languageName) with model: \(translationModel.rawValue)", source: "AppState")

                streamingTranslation = ""

                translationResult = try await llmService.translateStreaming(
                    text: llmResult.summarizedText,
                    targetLanguage: language,
                    model: translationModel,
                    systemPrompt: translationPrompt(for: language),
                    apiKey: effectiveApiKey,
                    onChunk: { [weak self] chunk in
                        guard let self = self else { return }
                        self.logger.debug("Translation chunk received: \(chunk.count) chars", source: "AppState")
                        self.streamingTranslation += chunk
                    }
                )

                logger.info("Translation complete: \(translationResult!.translatedText.count) chars", source: "AppState")
                textForTTS = translationResult!.translatedText
                isTranslating = false
            }

            // Now proceed with TTS
            currentText = textForTTS
            isPlaying = true
            isLoading = false

            // Reset tracking state
            accumulatedAudioData = Data()
            pendingHistorySave = nil
            historySaved = false

            // Set display text for highlighting (translated summary or just summary)
            displayText = textForTTS

            // Reset audio player for fresh playback (must be before setEstimatedDuration)
            audioPlayer.reset()
            audioPlayer.playbackSpeed = Float(playbackSpeed)
            audioPlayer.setEstimatedDuration(forTextLength: textForTTS.count)
            startProgressTracking()

            let voice = TTSVoice(rawValue: selectedVoice) ?? .coral
            logger.info("Using voice: \(voice.rawValue)", source: "AppState")

            // Store pending history with both summarization and translation metadata
            pendingHistorySave = (
                text: text,  // Original text
                voice: voice.rawValue,
                inputTokens: 0,
                summarizedText: llmResult.summarizedText,
                llmInputTokens: llmResult.inputTokens,
                llmOutputTokens: llmResult.outputTokens,
                llmModel: llmResult.model,
                translatedText: translationResult?.translatedText,
                translationInputTokens: translationResult?.inputTokens,
                translationOutputTokens: translationResult?.outputTokens,
                translationModel: translationResult?.model,
                targetLanguage: language != .none ? language.rawValue : nil
            )

            audioPlayer.onPlaybackComplete = { [weak self] in
                self?.logger.info("Audio playback complete", source: "AppState")
                Task { @MainActor in
                    self?.handlePlaybackComplete()
                }
            }

            audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)

            // TTS the final text
            logger.info("Starting TTS stream for summarized+translated text...", source: "AppState")
            ttsService.streamSpeech(
                text: textForTTS,
                voice: voice,
                apiKey: effectiveApiKey,
                onAudioChunk: { [weak self] data in
                    self?.logger.debug("Received audio chunk: \(data.count) bytes", source: "AppState")
                    self?.audioPlayer.enqueue(pcmData: data)
                    self?.accumulatedAudioData.append(data)
                },
                onComplete: { [weak self] result in
                    self?.logger.info("TTS stream complete, audio size: \(result.audioData.count) bytes, inputTokens: \(result.inputTokens)", source: "AppState")

                    if var pending = self?.pendingHistorySave {
                        pending.inputTokens = result.inputTokens
                        self?.pendingHistorySave = pending
                    }

                    self?.audioPlayer.markStreamComplete()
                },
                onError: { [weak self] error in
                    self?.logger.error("TTS error: \(error.localizedDescription)", source: "AppState")
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                        self?.isPlaying = false
                        self?.isSummarizing = false
                        self?.isTranslating = false
                        self?.audioLevelMonitor.stopMonitoring()
                    }
                }
            )
        } catch {
            logger.error("Summarize+Translate+TTS exception: \(error.localizedDescription)", source: "AppState")
            errorMessage = error.localizedDescription
            isLoading = false
            isPlaying = false
            isSummarizing = false
            isTranslating = false
        }
    }

    /// Update playback speed in real-time (also persists the setting)
    func updatePlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        audioPlayer.playbackSpeed = Float(speed)
        logger.debug("Playback speed updated to \(speed)x", source: "AppState")
    }

    /// Start tracking playback progress for text highlighting
    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackProgress()
            }
        }
    }

    /// Stop tracking playback progress
    private func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
        playbackProgress = 0.0
        highlightCharacterIndex = 0
        lastHighlightIndex = 0
    }

    /// Update playback progress and highlight position with smoothing
    @MainActor
    private func updatePlaybackProgress() {
        guard isPlaying, !displayText.isEmpty else { return }

        let rawProgress = audioPlayer.currentPlaybackProgress
        playbackProgress = rawProgress

        let targetIndex = Int(Double(displayText.count) * rawProgress)

        // Smoothing: only move forward, and limit step size for smooth animation
        // Allow backward movement only if it's a significant correction (>5% of text)
        let significantBackward = lastHighlightIndex - targetIndex > displayText.count / 20

        if targetIndex >= lastHighlightIndex {
            // Moving forward - smooth by limiting step size
            let maxStep = max(1, displayText.count / 100)  // ~1% of text per update
            highlightCharacterIndex = min(targetIndex, lastHighlightIndex + maxStep)
            lastHighlightIndex = highlightCharacterIndex
        } else if significantBackward {
            // Significant backward correction needed - allow it
            highlightCharacterIndex = targetIndex
            lastHighlightIndex = targetIndex
        }
        // Otherwise ignore small backward movements (jitter)
    }

    func stopPlayback() {
        logger.info("Stopping playback", source: "AppState")

        // Cancel ongoing summarization and translation tasks
        summarizationTask?.cancel()
        summarizationTask = nil
        translationTask?.cancel()
        translationTask = nil
        llmService.cancel()

        // Stop progress tracking
        stopProgressTracking()

        // Stop audio and TTS
        audioPlayer.stop()
        ttsService.cancel()
        audioLevelMonitor.stopMonitoring()

        // Save to history if we have accumulated audio and haven't saved yet
        if !historySaved, let pending = pendingHistorySave, !accumulatedAudioData.isEmpty {
            logger.info("Saving partial audio to history (\(accumulatedAudioData.count) bytes)", source: "AppState")
            HistoryManager.shared.addEntry(
                text: pending.text,
                voice: pending.voice,
                inputTokens: pending.inputTokens,
                audioData: accumulatedAudioData,
                summarizedText: pending.summarizedText,
                llmInputTokens: pending.llmInputTokens,
                llmOutputTokens: pending.llmOutputTokens,
                llmModel: pending.llmModel,
                translatedText: pending.translatedText,
                translationInputTokens: pending.translationInputTokens,
                translationOutputTokens: pending.translationOutputTokens,
                translationModel: pending.translationModel,
                targetLanguage: pending.targetLanguage
            )
            historySaved = true
        }

        // Clear state
        isPlaying = false
        isSummarizing = false
        isTranslating = false
        currentText = nil
        streamingSummary = ""
        streamingTranslation = ""
        displayText = ""
        accumulatedAudioData = Data()
        pendingHistorySave = nil
    }

    @MainActor
    private func handlePlaybackComplete() {
        guard isPlaying else { return }

        logger.info("Playback completed naturally", source: "AppState")

        // Save to history if not already saved
        if !historySaved, let pending = pendingHistorySave, !accumulatedAudioData.isEmpty {
            logger.info("Saving to history (\(accumulatedAudioData.count) bytes)", source: "AppState")
            HistoryManager.shared.addEntry(
                text: pending.text,
                voice: pending.voice,
                inputTokens: pending.inputTokens,
                audioData: accumulatedAudioData,
                summarizedText: pending.summarizedText,
                llmInputTokens: pending.llmInputTokens,
                llmOutputTokens: pending.llmOutputTokens,
                llmModel: pending.llmModel,
                translatedText: pending.translatedText,
                translationInputTokens: pending.translationInputTokens,
                translationOutputTokens: pending.translationOutputTokens,
                translationModel: pending.translationModel,
                targetLanguage: pending.targetLanguage
            )
            historySaved = true
        }

        // Stop progress tracking and monitoring
        stopProgressTracking()
        audioLevelMonitor.stopMonitoring()
        isPlaying = false
        currentText = nil
        streamingSummary = ""
        streamingTranslation = ""
        displayText = ""
        accumulatedAudioData = Data()
        pendingHistorySave = nil
    }
}
