import SwiftUI
import KeyboardShortcuts
import NaturalLanguage
import HibikiPocketRuntime

/// Position options for the audio player panel
enum PanelPosition: String, CaseIterable, Identifiable {
    case topRight = "topRight"
    case topLeft = "topLeft"
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"
    case belowMenuBar = "belowMenuBar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        case .belowMenuBar: return "Below Menu Bar"
        }
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    static let defaultSummarizationPrompt = """
        Summarize the following text in an ultra-concise, dense summary that captures only the essential facts. \
        Omit examples, tangents, filler, and secondary details. The summary should be suitable for text-to-speech, \
        so write in complete sentences and avoid bullet points or special formatting. Remove any links, URLs, or emojis. \
        Aim for 3–5 sentences and no more than 2 short paragraphs.
        """
    static let maxPlaybackVolume: Double = 3.0
    private static let legacySummarizationPrompts: [String] = [
        """
        Summarize the following text concisely while preserving the key information. \
        The summary should be suitable for text-to-speech, so write in complete sentences \
        and avoid bullet points or special formatting. Keep it under 3 paragraphs.
        """,
        """
        Summarize the following text in a concise, dense summary while preserving the key information. \
        The summary should be suitable for text-to-speech, so write in complete sentences \
        and avoid bullet points or special formatting. Remove any links, URLs, or emojis. \
        Keep it under 3 paragraphs.
        """
    ]

    @Published var isPlaying = false {
        didSet {
            if !isPlaying {
                isPaused = false
            }
        }
    }
    @Published var isPaused = false
    @Published var isLoading = false
    @Published var isSummarizing = false
    @Published var isTranslating = false
    @Published var currentText: String?
    @Published var errorMessage: String?
    @Published var streamingSummary: String = ""  // Accumulates streaming summary text
    @Published var streamingTranslation: String = ""  // Accumulates streaming translation text

    /// Timestamp of when a hotkey was last triggered (used to prevent Option-only stop during cooldown)
    /// Thread-safe access via lock since it's read from keyboard monitor (non-main thread)
    private let hotkeyTimeLock = NSLock()
    private var _lastHotkeyTriggerTime: Date?
    var lastHotkeyTriggerTime: Date? {
        get { hotkeyTimeLock.lock(); defer { hotkeyTimeLock.unlock() }; return _lastHotkeyTriggerTime }
        set { hotkeyTimeLock.lock(); defer { hotkeyTimeLock.unlock() }; _lastHotkeyTriggerTime = newValue }
    }

    // Text highlighting during playback
    @Published var playbackProgress: Double = 0.0
    @Published var highlightCharacterIndex: Int = 0
    @Published var displayText: String = ""  // Text being spoken (raw/summarized/translated)
    @Published var activeHistoryReplayEntryId: UUID?
    @Published private(set) var pendingRequestCount: Int = 0

    @AppStorage("selectedVoice") var selectedVoice: String = TTSVoice.coral.rawValue
    @AppStorage("ttsProvider") var ttsProvider: String = TTSProvider.openAI.rawValue
    @AppStorage("openaiAPIKey") var apiKey: String = ""
    @AppStorage("elevenLabsAPIKey") var elevenLabsAPIKey: String = ""
    @AppStorage("elevenLabsVoiceID") var elevenLabsVoiceID: String = "JBFqnCBsd6RMkjVDRZzb"
    @AppStorage("elevenLabsModelID") var elevenLabsModelID: String = TTSConfiguration.defaultElevenLabsModelID
    @AppStorage("pocketBaseURL") var pocketBaseURL: String = TTSConfiguration.defaultPocketBaseURL
    @AppStorage("pocketVoiceURL") var pocketVoiceURL: String = TTSConfiguration.defaultPocketVoiceURL
    @AppStorage("pocketRequestTimeoutSec") var pocketRequestTimeoutSec: Double = TTSConfiguration.defaultPocketRequestTimeoutSec
    @AppStorage("pocketManagedEnabled") var pocketManagedEnabled: Bool = false
    @AppStorage("pocketManagedAutoStart") var pocketManagedAutoStart: Bool = true
    @AppStorage("pocketManagedHost") var pocketManagedHost: String = "127.0.0.1"
    @AppStorage("pocketManagedPort") var pocketManagedPort: Int = 8000
    @AppStorage("pocketManagedVenvPath") var pocketManagedVenvPath: String = PocketTTSRuntimeManager.defaultVenvPath()
    @AppStorage("pocketManagedVoiceURL") var pocketManagedVoiceURL: String = TTSConfiguration.defaultPocketVoiceURL
    @AppStorage("pocketManagedLastError") var pocketManagedLastError: String = ""
    @AppStorage("playbackSpeed") var playbackSpeed: Double = 1.0
    @AppStorage("playbackVolume") var playbackVolume: Double = 1.0
    @AppStorage(HistoryManager.retentionDaysDefaultsKey) var historyRetentionDays: Int = HistoryManager.defaultRetentionDays
    @AppStorage(HistoryManager.maxEntriesDefaultsKey) var historyRetentionMaxEntries: Int = HistoryManager.defaultMaxEntries
    @AppStorage(HistoryManager.maxDiskSpaceDefaultsKey) var historyRetentionMaxDiskSpaceMB: Double = HistoryManager.defaultMaxDiskSpaceMB

    // Panel position and collapse settings
    @AppStorage("panelPosition") var panelPosition: String = PanelPosition.topRight.rawValue
    @Published var isPanelCollapsed: Bool = false

    // Summarization settings
    @AppStorage("summarizationModel") var summarizationModel: String = LLMModel.gpt5Nano.rawValue
    @AppStorage("summarizationPrompt") var summarizationPrompt: String = AppState.defaultSummarizationPrompt

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
    let pocketRuntimeManager = PocketTTSRuntimeManager.shared
    private var summarizationTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?
    private let interleavedPipeline = InterleavedPipeline()

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
    private enum RequestSource: String {
        case cli
        case manual
        case settings

        var logSource: String {
            switch self {
            case .cli: return "CLI"
            case .manual: return "Manual"
            case .settings: return "Settings"
            }
        }
    }

    private struct QueuedRequest {
        let source: RequestSource
        let text: String
        let shouldSummarize: Bool
        let targetLanguage: TargetLanguage?
        let summarizationPromptOverride: String?
        let ttsConfigurationOverride: TTSConfiguration?
    }
    private var requestQueue: [QueuedRequest] = []
    private var activeRequest: QueuedRequest?

    @MainActor
    private func syncRequestQueueState() {
        pendingRequestCount = requestQueue.count + (activeRequest == nil ? 0 : 1)
    }

    @MainActor
    private func resetAccumulatedAudioData() {
        accumulatedAudioData = Data()
    }

    @MainActor
    private func appendAccumulatedAudioData(_ dataChunk: Data) {
        accumulatedAudioData.append(dataChunk)
    }

    @MainActor
    private func takeAccumulatedAudioSnapshot() -> Data {
        guard !accumulatedAudioData.isEmpty else { return Data() }
        let snapshot = accumulatedAudioData
        accumulatedAudioData = Data()
        return snapshot
    }

    @MainActor
    private func enqueueRequest(
        source: RequestSource,
        text: String,
        shouldSummarize: Bool,
        targetLanguage: TargetLanguage?,
        summarizationPromptOverride: String?,
        ttsConfigurationOverride: TTSConfiguration? = nil
    ) {
        let request = QueuedRequest(
            source: source,
            text: text,
            shouldSummarize: shouldSummarize,
            targetLanguage: targetLanguage,
            summarizationPromptOverride: summarizationPromptOverride,
            ttsConfigurationOverride: ttsConfigurationOverride
        )
        requestQueue.append(request)
        syncRequestQueueState()
        logger.info(
            "Queued \(source.rawValue) request. active=\(activeRequest != nil), waiting=\(requestQueue.count)",
            source: source.logSource
        )
    }

    @MainActor
    private func processNextRequestIfPossible() {
        guard activeRequest == nil else { return }
        guard !isPlaying, !isLoading, !isSummarizing, !isTranslating else { return }
        guard !requestQueue.isEmpty else { return }

        let request = requestQueue.removeFirst()
        activeRequest = request
        syncRequestQueueState()
        logger.info(
            "Starting queued \(request.source.rawValue) request. remaining=\(requestQueue.count)",
            source: request.source.logSource
        )

        Task { @MainActor in
            await self.startQueuedRequest(request)
        }
    }

    @MainActor
    private func markRequestFinished(startNext: Bool = true) {
        if let currentRequest = activeRequest {
            logger.info("\(currentRequest.source.rawValue) request finished", source: currentRequest.source.logSource)
            activeRequest = nil
            syncRequestQueueState()
        }

        if startNext {
            processNextRequestIfPossible()
        }
    }

    @MainActor
    private func clearRequestQueue() {
        if activeRequest != nil || !requestQueue.isEmpty {
            logger.info("Clearing request queue (active + waiting requests)", source: "Queue")
        }
        activeRequest = nil
        requestQueue.removeAll()
        syncRequestQueueState()
    }

    init() {
        migrateSummarizationPromptIfNeeded()
        if elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            elevenLabsVoiceID = "JBFqnCBsd6RMkjVDRZzb"
        }
        if ElevenLabsModel(rawValue: elevenLabsModelID) == nil {
            elevenLabsModelID = TTSConfiguration.defaultElevenLabsModelID
        }
        // Default OpenAI key from environment variable if not set
        if apiKey.isEmpty,
           let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
           !envKey.isEmpty {
            apiKey = envKey
            logger.info("Loaded OpenAI API key from OPENAI_API_KEY", source: "AppState")
        }
        // Default ElevenLabs key from environment variable if not set
        if elevenLabsAPIKey.isEmpty,
           let envKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"],
           !envKey.isEmpty {
            elevenLabsAPIKey = envKey
            logger.info("Loaded ElevenLabs API key from ELEVENLABS_API_KEY", source: "AppState")
        }
        if pocketBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let envBaseURL = ProcessInfo.processInfo.environment["POCKET_TTS_BASE_URL"],
           !envBaseURL.isEmpty {
            pocketBaseURL = envBaseURL
            logger.info("Loaded Pocket TTS base URL from POCKET_TTS_BASE_URL", source: "AppState")
        }
        if pocketManagedVenvPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pocketManagedVenvPath = PocketTTSRuntimeManager.defaultVenvPath()
        }
        let clampedVolume = min(Self.maxPlaybackVolume, max(0.0, playbackVolume))
        if clampedVolume != playbackVolume {
            playbackVolume = clampedVolume
        }
        audioPlayer.playbackVolume = Float(clampedVolume)
        setupHotkeyHandler()
        logger.info("AppState initialized, hotkey handler registered", source: "AppState")

        if pocketManagedEnabled,
           pocketManagedAutoStart,
           activeTTSProvider() == .pocketLocal {
            Task { @MainActor [weak self] in
                await self?.ensurePocketRuntimeStarted(logSource: "AppState")
            }
        }
    }

    private func migrateSummarizationPromptIfNeeded() {
        let normalized = summarizationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLegacy = Self.legacySummarizationPrompts.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }
        if isLegacy {
            summarizationPrompt = Self.defaultSummarizationPrompt
            logger.info("Updated legacy summarization prompt to latest default", source: "AppState")
        }
    }

    private func activeTTSProvider() -> TTSProvider {
        if let provider = TTSProvider(rawValue: ttsProvider) {
            return provider
        }
        ttsProvider = TTSProvider.openAI.rawValue
        return .openAI
    }

    private func resolveOpenAIAPIKey(logSource: String) -> String? {
        if !apiKey.isEmpty {
            return apiKey
        }

        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            apiKey = envKey
            logger.info("Loaded OpenAI API key from OPENAI_API_KEY", source: logSource)
            return envKey
        }

        return nil
    }

    private func resolveElevenLabsAPIKey(logSource: String) -> String? {
        if !elevenLabsAPIKey.isEmpty {
            return elevenLabsAPIKey
        }

        if let envKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], !envKey.isEmpty {
            elevenLabsAPIKey = envKey
            logger.info("Loaded ElevenLabs API key from ELEVENLABS_API_KEY", source: logSource)
            return envKey
        }

        return nil
    }

    private func managedPocketBaseURL() -> String {
        PocketTTSRuntimeManager.baseURL(host: pocketManagedHost, port: pocketManagedPort)
    }

    private func effectivePocketVoice() -> String {
        let managedVoice = pocketManagedVoiceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if pocketManagedEnabled, !managedVoice.isEmpty {
            return managedVoice
        }
        let configuredVoice = pocketVoiceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return configuredVoice.isEmpty ? TTSConfiguration.defaultPocketVoiceURL : configuredVoice
    }

    private func resolvePocketBaseURL(logSource: String) -> String? {
        if pocketManagedEnabled {
            return managedPocketBaseURL()
        }

        let configuredBaseURL = pocketBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredBaseURL.isEmpty {
            return configuredBaseURL
        }

        if let envURL = ProcessInfo.processInfo.environment["POCKET_TTS_BASE_URL"],
           !envURL.isEmpty {
            pocketBaseURL = envURL
            logger.info("Loaded Pocket base URL from POCKET_TTS_BASE_URL", source: logSource)
            return envURL
        }

        return nil
    }

    private func resolveTTSConfiguration(logSource: String, openAIAPIKeyOverride: String? = nil) -> TTSConfiguration? {
        let provider = activeTTSProvider()
        let openAIVoice = TTSVoice(rawValue: selectedVoice) ?? .coral

        switch provider {
        case .openAI:
            guard let openAIKey = openAIAPIKeyOverride ?? resolveOpenAIAPIKey(logSource: logSource) else {
                logger.error("OpenAI API key is empty!", source: logSource)
                errorMessage = "No OpenAI API key configured. Enter key in Settings or set OPENAI_API_KEY."
                return nil
            }

            return TTSConfiguration(
                provider: .openAI,
                openAIAPIKey: openAIKey,
                openAIVoice: openAIVoice,
                elevenLabsAPIKey: "",
                elevenLabsVoiceID: "",
                elevenLabsModelID: elevenLabsModelID,
                pocketBaseURL: pocketBaseURL,
                pocketVoiceURL: pocketVoiceURL,
                pocketRequestTimeoutSec: pocketRequestTimeoutSec,
                instructions: TTSConfiguration.defaultInstructions
            )

        case .elevenLabs:
            guard let elevenLabsKey = resolveElevenLabsAPIKey(logSource: logSource) else {
                logger.error("ElevenLabs API key is empty!", source: logSource)
                errorMessage = "No ElevenLabs API key configured. Enter key in Settings or set ELEVENLABS_API_KEY."
                return nil
            }

            let voiceID = elevenLabsVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !voiceID.isEmpty else {
                logger.error("ElevenLabs voice ID is empty!", source: logSource)
                errorMessage = "No ElevenLabs voice ID configured. Enter voice ID in Settings."
                return nil
            }

            return TTSConfiguration(
                provider: .elevenLabs,
                openAIAPIKey: openAIAPIKeyOverride ?? "",
                openAIVoice: openAIVoice,
                elevenLabsAPIKey: elevenLabsKey,
                elevenLabsVoiceID: voiceID,
                elevenLabsModelID: elevenLabsModelID,
                pocketBaseURL: pocketBaseURL,
                pocketVoiceURL: pocketVoiceURL,
                pocketRequestTimeoutSec: pocketRequestTimeoutSec,
                instructions: TTSConfiguration.defaultInstructions
            )

        case .pocketLocal:
            guard let baseURL = resolvePocketBaseURL(logSource: logSource) else {
                logger.error("Pocket TTS base URL is empty!", source: logSource)
                errorMessage = "No Pocket TTS URL configured. Enter URL in Settings or set POCKET_TTS_BASE_URL."
                return nil
            }

            return TTSConfiguration(
                provider: .pocketLocal,
                openAIAPIKey: openAIAPIKeyOverride ?? "",
                openAIVoice: openAIVoice,
                elevenLabsAPIKey: "",
                elevenLabsVoiceID: "",
                elevenLabsModelID: elevenLabsModelID,
                pocketBaseURL: baseURL,
                pocketVoiceURL: effectivePocketVoice(),
                pocketRequestTimeoutSec: pocketRequestTimeoutSec,
                instructions: TTSConfiguration.defaultInstructions
            )
        }
    }

    @MainActor
    func installPocketRuntime() async {
        do {
            try await pocketRuntimeManager.reinstall(venvPath: pocketManagedVenvPath)
            pocketManagedLastError = ""
            errorMessage = nil
        } catch {
            pocketManagedLastError = error.localizedDescription
            errorMessage = error.localizedDescription
            logger.error("Pocket runtime install failed: \(error.localizedDescription)", source: "AppState")
        }
    }

    @MainActor
    func startPocketRuntime() async {
        await ensurePocketRuntimeStarted(logSource: "Settings")
    }

    @MainActor
    func stopPocketRuntime() {
        pocketRuntimeManager.stopServer()
    }

    @MainActor
    func restartPocketRuntime() async {
        do {
            try await pocketRuntimeManager.restartServer(
                host: pocketManagedHost,
                port: pocketManagedPort,
                voice: effectivePocketVoice(),
                venvPath: pocketManagedVenvPath,
                autoRestart: pocketManagedAutoStart
            )
            pocketManagedLastError = ""
            errorMessage = nil
        } catch {
            pocketManagedLastError = error.localizedDescription
            errorMessage = error.localizedDescription
            logger.error("Pocket runtime restart failed: \(error.localizedDescription)", source: "Settings")
        }
    }

    @MainActor
    func runPocketRuntimeHealthCheck() async -> PocketRuntimeHealth {
        let baseURL = pocketManagedEnabled ? managedPocketBaseURL() : pocketBaseURL
        return await pocketRuntimeManager.healthCheck(baseURL: baseURL)
    }

    @MainActor
    func runPocketRuntimeHealthCheckWithReadout() async {
        let health = await runPocketRuntimeHealthCheck()
        guard health.isHealthy else {
            errorMessage = health.message ?? "Pocket health check failed."
            return
        }

        let baseURL = pocketManagedEnabled ? managedPocketBaseURL() : pocketBaseURL
        let healthCheckConfiguration = TTSConfiguration(
            provider: .pocketLocal,
            openAIAPIKey: "",
            openAIVoice: TTSVoice(rawValue: selectedVoice) ?? .coral,
            elevenLabsAPIKey: "",
            elevenLabsVoiceID: "",
            elevenLabsModelID: elevenLabsModelID,
            pocketBaseURL: baseURL,
            pocketVoiceURL: effectivePocketVoice(),
            pocketRequestTimeoutSec: pocketRequestTimeoutSec,
            instructions: TTSConfiguration.defaultInstructions
        )

        errorMessage = nil
        enqueueRequest(
            source: .settings,
            text: "Pocket TTS health check successful.",
            shouldSummarize: false,
            targetLanguage: nil,
            summarizationPromptOverride: nil,
            ttsConfigurationOverride: healthCheckConfiguration
        )
        processNextRequestIfPossible()
    }

    @MainActor
    private func ensurePocketRuntimeStarted(logSource: String) async {
        guard pocketManagedEnabled else { return }

        do {
            try await pocketRuntimeManager.installIfNeeded(venvPath: pocketManagedVenvPath)

            let portsToTry = candidateManagedPocketPorts(startingAt: pocketManagedPort)
            var started = false
            var lastStartupError: Error?

            for port in portsToTry {
                let baseURL = PocketTTSRuntimeManager.baseURL(host: pocketManagedHost, port: port)
                let health = await pocketRuntimeManager.healthCheck(baseURL: baseURL)
                if health.isHealthy {
                    if pocketManagedPort != port {
                        logger.warning("Switching Pocket managed port to \(port) because configured port is unavailable", source: logSource)
                        pocketManagedPort = port
                    }
                    started = true
                    break
                }

                // Non-pocket service already using this port (e.g. Python HTTP server).
                if health.statusCode != nil, !health.isPocketAPI {
                    logger.warning("Port \(port) is occupied by a non-Pocket service, skipping.", source: logSource)
                    continue
                }

                do {
                    try await pocketRuntimeManager.startServer(
                        host: pocketManagedHost,
                        port: port,
                        voice: effectivePocketVoice(),
                        venvPath: pocketManagedVenvPath,
                        autoRestart: pocketManagedAutoStart
                    )
                    let postStartHealth = await pocketRuntimeManager.healthCheck(baseURL: baseURL)
                    if postStartHealth.isHealthy {
                        if pocketManagedPort != port {
                            logger.warning("Using fallback Pocket managed port \(port)", source: logSource)
                            pocketManagedPort = port
                        }
                        started = true
                        break
                    }
                } catch {
                    lastStartupError = error
                }
            }

            guard started else {
                if let lastStartupError {
                    throw lastStartupError
                }
                throw PocketRuntimeError.healthCheckFailed
            }

            pocketManagedLastError = ""
        } catch {
            pocketManagedLastError = error.localizedDescription
            errorMessage = error.localizedDescription
            logger.error("Pocket runtime startup failed: \(error.localizedDescription)", source: logSource)
        }
    }

    private func candidateManagedPocketPorts(startingAt startPort: Int) -> [Int] {
        let safeStart = max(1025, min(65500, startPort))
        var ports: [Int] = [safeStart]
        for offset in 1...5 {
            let candidate = safeStart + offset
            if candidate <= 65535 {
                ports.append(candidate)
            }
        }
        return ports
    }

    private func pocketLanguageIsAllowed(_ text: String) -> Bool {
        guard activeTTSProvider() == .pocketLocal else {
            return true
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return true
        }

        let letterCount = normalized.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.letters.contains(scalar) {
                count += 1
            }
        }

        guard letterCount >= 12 else {
            return true
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalized)
        guard let dominantLanguage = recognizer.dominantLanguage else {
            return true
        }

        return dominantLanguage == .english || dominantLanguage == .undetermined
    }

    private func setupHotkeyHandler() {
        logger.debug("Setting up hotkey handler for .triggerTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerTTS) { [weak self] in
            self?.logger.info("Hotkey pressed!", source: "AppState")
            self?.lastHotkeyTriggerTime = Date()
            Task { @MainActor in
                await self?.handleHotkeyPressed()
            }
        }

        logger.debug("Setting up hotkey handler for .triggerSummarizeTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerSummarizeTTS) { [weak self] in
            self?.logger.info("Summarize+TTS hotkey pressed!", source: "AppState")
            self?.lastHotkeyTriggerTime = Date()
            self?.summarizationTask?.cancel()
            self?.summarizationTask = Task { @MainActor in
                await self?.handleSummarizeTTSPressed()
            }
        }

        logger.debug("Setting up hotkey handler for .triggerTranslateTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerTranslateTTS) { [weak self] in
            self?.logger.info("Translate+TTS hotkey pressed!", source: "AppState")
            self?.lastHotkeyTriggerTime = Date()
            self?.translationTask?.cancel()
            self?.translationTask = Task { @MainActor in
                await self?.handleTranslateTTSPressed()
            }
        }

        logger.debug("Setting up hotkey handler for .triggerSummarizeTranslateTTS", source: "AppState")
        KeyboardShortcuts.onKeyDown(for: .triggerSummarizeTranslateTTS) { [weak self] in
            self?.logger.info("Summarize+Translate+TTS hotkey pressed!", source: "AppState")
            self?.lastHotkeyTriggerTime = Date()
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

        if isPaused {
            logger.info("Hotkey pressed while paused, resuming playback", source: "AppState")
            resumePlayback()
            return
        }

        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        await enqueueManualRequest(shouldSummarize: false, targetLanguage: nil)
    }

    @MainActor
    func handleSummarizeTTSPressed() async {
        logger.debug("handleSummarizeTTSPressed called", source: "AppState")

        if isPaused {
            logger.info("Summarize+TTS hotkey pressed while paused, resuming playback", source: "AppState")
            resumePlayback()
            return
        }

        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        await enqueueManualRequest(shouldSummarize: true, targetLanguage: nil)
    }

    @MainActor
    func handleTranslateTTSPressed() async {
        logger.debug("handleTranslateTTSPressed called", source: "AppState")

        if isPaused {
            logger.info("Translate+TTS hotkey pressed while paused, resuming playback", source: "AppState")
            resumePlayback()
            return
        }

        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        let language = TargetLanguage(rawValue: targetLanguage) ?? .none
        await enqueueManualRequest(
            shouldSummarize: false,
            targetLanguage: language == .none ? nil : language
        )
    }

    @MainActor
    func handleSummarizeTranslateTTSPressed() async {
        logger.debug("handleSummarizeTranslateTTSPressed called", source: "AppState")

        if isPaused {
            logger.info("Summarize+Translate+TTS hotkey pressed while paused, resuming playback", source: "AppState")
            resumePlayback()
            return
        }

        if isPlaying {
            logger.info("Already playing, stopping playback", source: "AppState")
            stopPlayback()
            return
        }

        let language = TargetLanguage(rawValue: targetLanguage) ?? .none
        await enqueueManualRequest(
            shouldSummarize: true,
            targetLanguage: language == .none ? nil : language
        )
    }

    @MainActor
    private func enqueueManualRequest(
        shouldSummarize: Bool,
        targetLanguage: TargetLanguage?
    ) async {
        requestPanelPinForManualSelection()

        do {
            logger.debug("Attempting to get selected text for manual request", source: "Manual")
            guard let rawText = try accessibilityManager.getSelectedText(),
                  !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                logger.error("No text selected", source: "Manual")
                errorMessage = "No text selected"
                return
            }

            errorMessage = nil

            enqueueRequest(
                source: .manual,
                text: rawText,
                shouldSummarize: shouldSummarize,
                targetLanguage: targetLanguage,
                summarizationPromptOverride: nil,
                ttsConfigurationOverride: nil
            )
            processNextRequestIfPossible()
        } catch {
            logger.error("Manual request failed: \(error.localizedDescription)", source: "Manual")
            errorMessage = error.localizedDescription
        }
    }

    /// Update playback speed in real-time (also persists the setting)
    func updatePlaybackSpeed(_ speed: Double) {
        playbackSpeed = speed
        audioPlayer.playbackSpeed = Float(speed)
        logger.debug("Playback speed updated to \(speed)x", source: "AppState")
    }

    @MainActor
    private func requestPanelPinForManualSelection() {
        NotificationCenter.default.post(name: .hibikiPinPanelToManualSelection, object: nil)
    }

    /// Pause playback without stopping TTS streaming
    func pausePlayback() {
        guard isPlaying, !isPaused else { return }
        audioPlayer.pause()
        isPaused = true
        logger.debug("Playback paused", source: "AppState")
    }

    /// Resume playback after pause
    func resumePlayback() {
        guard isPlaying, isPaused else { return }
        audioPlayer.resume()
        isPaused = false
        logger.debug("Playback resumed", source: "AppState")
    }

    /// Toggle pause/resume for current playback
    func togglePlaybackPause() {
        if isPaused {
            resumePlayback()
        } else {
            pausePlayback()
        }
    }

    /// Play/pause a specific transcribed audio track from history
    @MainActor
    func toggleHistoryPlayback(for entry: HistoryEntry) {
        if isPlaying, activeHistoryReplayEntryId == entry.id {
            togglePlaybackPause()
            return
        }

        if isPlaying || isSummarizing || isTranslating || isLoading {
            stopPlayback()
        }

        guard let audioData = HistoryManager.shared.getAudioData(for: entry), !audioData.isEmpty else {
            errorMessage = "Failed to load the selected transcribed audio track."
            return
        }

        playHistoryEntry(entry, audioData: audioData)
    }

    /// Play/pause the most recent transcribed audio track from history
    @MainActor
    func toggleLatestHistoryPlayback() {
        guard let latestEntry = HistoryManager.shared.entries.first else {
            errorMessage = "No transcribed audio track found in history."
            return
        }
        toggleHistoryPlayback(for: latestEntry)
    }

    /// Update playback volume in real-time (also persists the setting)
    func updatePlaybackVolume(_ volume: Double) {
        let clamped = min(Self.maxPlaybackVolume, max(0.0, volume))
        playbackVolume = clamped
        audioPlayer.playbackVolume = Float(clamped)
        logger.debug("Playback volume updated to \(Int(clamped * 100))%", source: "AppState")
    }

    @MainActor
    private func playHistoryEntry(_ entry: HistoryEntry, audioData: Data) {
        logger.info("Replaying history entry: \(entry.id)", source: "AppState")

        errorMessage = nil
        isLoading = false
        isSummarizing = false
        isTranslating = false
        isPlaying = true
        isPaused = false
        activeHistoryReplayEntryId = entry.id

        currentText = entry.displayText
        displayText = entry.displayText
        streamingSummary = ""
        streamingTranslation = ""
        playbackProgress = 0.0
        highlightCharacterIndex = 0
        lastHighlightIndex = 0

        resetAccumulatedAudioData()
        pendingHistorySave = nil
        historySaved = true  // Replay should not create a new history entry

        audioPlayer.reset()
        audioPlayer.playbackSpeed = Float(playbackSpeed)
        audioPlayer.playbackVolume = Float(playbackVolume)
        audioPlayer.setEstimatedDuration(forTextLength: max(1, entry.displayText.count))
        audioPlayer.onPlaybackComplete = { [weak self] in
            self?.logger.info("History replay complete", source: "AppState")
            Task { @MainActor in
                self?.handlePlaybackComplete()
            }
        }

        let chunkSize = 8192
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + chunkSize, audioData.count)
            audioPlayer.enqueue(pcmData: Data(audioData[offset..<end]))
            offset = end
        }
        audioPlayer.markStreamComplete()

        audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)
        startProgressTracking()
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
        if isPaused {
            return
        }

        // Visual lead keeps highlights perceptually aligned with speech output,
        // especially while streaming where duration is still estimated.
        let leadProgress = min(0.05, (0.008 * playbackSpeed) + 0.006)
        let adjustedProgress = min(1.0, rawProgress + leadProgress)
        let targetIndex = Int(Double(displayText.count) * adjustedProgress)

        // Smoothing: only move forward, and limit step size for smooth animation
        // Allow backward movement only if it's a significant correction (>5% of text)
        let significantBackward = lastHighlightIndex - targetIndex > displayText.count / 20

        if targetIndex >= lastHighlightIndex {
            // Move forward with adaptive catch-up speed when we're behind.
            let delta = targetIndex - lastHighlightIndex
            let minStep = playbackSpeed >= 1.6 ? 2 : 1
            let adaptiveStep = max(minStep, Int(ceil(Double(delta) * 0.45)))
            highlightCharacterIndex = min(targetIndex, lastHighlightIndex + adaptiveStep)
            lastHighlightIndex = highlightCharacterIndex
        } else if significantBackward {
            // Significant backward correction needed - allow it
            highlightCharacterIndex = targetIndex
            lastHighlightIndex = targetIndex
        }
        // Otherwise ignore small backward movements (jitter)
    }

    @MainActor
    func stopPlayback() {
        logger.info("Stopping playback", source: "AppState")

        // Cancel ongoing summarization and translation tasks
        summarizationTask?.cancel()
        summarizationTask = nil
        translationTask?.cancel()
        translationTask = nil
        llmService.cancel()
        interleavedPipeline.cancel()

        // Stop progress tracking
        stopProgressTracking()

        // Stop audio and TTS
        audioPlayer.stop()
        ttsService.cancel()
        audioLevelMonitor.stopMonitoring()

        // Save to history if we have accumulated audio and haven't saved yet
        let audioSnapshot = takeAccumulatedAudioSnapshot()

        if !historySaved, let pending = pendingHistorySave, !audioSnapshot.isEmpty {
            logger.info("Saving partial audio to history (\(audioSnapshot.count) bytes)", source: "AppState")
            HistoryManager.shared.addEntry(
                text: pending.text,
                voice: pending.voice,
                inputTokens: pending.inputTokens,
                audioData: audioSnapshot,
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
        activeHistoryReplayEntryId = nil
        currentText = nil
        streamingSummary = ""
        streamingTranslation = ""
        displayText = ""
        resetAccumulatedAudioData()
        pendingHistorySave = nil
        clearRequestQueue()
    }

    @MainActor
    private func handlePlaybackComplete() {
        guard isPlaying else { return }

        logger.info("Playback completed naturally", source: "AppState")

        // Save to history if not already saved
        let audioSnapshot = takeAccumulatedAudioSnapshot()

        if !historySaved, let pending = pendingHistorySave, !audioSnapshot.isEmpty {
            logger.info("Saving to history (\(audioSnapshot.count) bytes)", source: "AppState")
            HistoryManager.shared.addEntry(
                text: pending.text,
                voice: pending.voice,
                inputTokens: pending.inputTokens,
                audioData: audioSnapshot,
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
        activeHistoryReplayEntryId = nil
        currentText = nil
        streamingSummary = ""
        streamingTranslation = ""
        displayText = ""
        resetAccumulatedAudioData()
        pendingHistorySave = nil
        markRequestFinished()
    }

    // MARK: - Queued Request Processing

    /// Process text provided directly from CLI (bypassing AccessibilityManager)
    /// - Parameters:
    ///   - text: The text to process
    ///   - shouldSummarize: Whether to summarize the text first
    ///   - targetLanguage: Optional target language for translation
    ///   - summarizationPromptOverride: Optional prompt override for summarization
    @MainActor
    func processTextFromCLI(
        text: String,
        shouldSummarize: Bool,
        targetLanguage: TargetLanguage?,
        summarizationPromptOverride: String?
    ) async {
        enqueueRequest(
            source: .cli,
            text: text,
            shouldSummarize: shouldSummarize,
            targetLanguage: targetLanguage,
            summarizationPromptOverride: summarizationPromptOverride,
            ttsConfigurationOverride: nil
        )
        processNextRequestIfPossible()
    }

    @MainActor
    private func startQueuedRequest(_ request: QueuedRequest) async {
        let source = request.source
        let logSource = source.logSource
        let text = request.text
        let shouldSummarize = request.shouldSummarize
        let targetLanguage = request.targetLanguage
        let summarizationPromptOverride = request.summarizationPromptOverride

        let promptLabel = summarizationPromptOverride == nil ? "default" : "custom"
        logger.info(
            "Queued request started: source=\(source.rawValue), summarize=\(shouldSummarize), prompt=\(promptLabel), translate=\(targetLanguage?.rawValue ?? "none"), text=\(text.prefix(50))...",
            source: logSource
        )

        let language = targetLanguage ?? .none
        let summarizationPromptToUse = summarizationPromptOverride ?? summarizationPrompt
        let provider = request.ttsConfigurationOverride?.provider ?? activeTTSProvider()
        let requiresOpenAIForLLM = shouldSummarize || language != .none

        if provider == .pocketLocal, !pocketManagedEnabled {
            let configuredBaseURL: String = {
                let trimmed = pocketBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return TTSConfiguration.defaultPocketBaseURL }
                if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    return trimmed
                }
                return "http://\(trimmed)"
            }()

            let manualHealth = await pocketRuntimeManager.healthCheck(baseURL: configuredBaseURL)
            if manualHealth.isHealthy {
                pocketBaseURL = configuredBaseURL
            } else if !manualHealth.isPocketAPI,
                      pocketRuntimeManager.hasInstalledRuntime(venvPath: pocketManagedVenvPath) {
                logger.warning(
                    "Configured Pocket endpoint is not Pocket API (\(configuredBaseURL)); switching to managed runtime.",
                    source: logSource
                )
                pocketManagedEnabled = true
            }
        }

        let openAIAPIKey: String?
        if requiresOpenAIForLLM || provider == .openAI {
            guard let resolved = resolveOpenAIAPIKey(logSource: logSource) else {
                logger.error("OpenAI API key is empty!", source: logSource)
                errorMessage = "No OpenAI API key configured. Enter key in Settings or set OPENAI_API_KEY."
                markRequestFinished()
                return
            }
            openAIAPIKey = resolved
        } else {
            openAIAPIKey = nil
        }

        if provider == .pocketLocal, pocketManagedEnabled {
            await ensurePocketRuntimeStarted(logSource: logSource)
            if !pocketManagedLastError.isEmpty {
                markRequestFinished()
                return
            }
        }

        let ttsConfiguration: TTSConfiguration
        if let overrideConfiguration = request.ttsConfigurationOverride {
            ttsConfiguration = overrideConfiguration
        } else {
            guard let resolved = resolveTTSConfiguration(logSource: logSource, openAIAPIKeyOverride: openAIAPIKey) else {
                markRequestFinished()
                return
            }
            ttsConfiguration = resolved
        }

        if provider == .pocketLocal, !pocketLanguageIsAllowed(text) {
            logger.error("Pocket TTS only supports English text right now", source: logSource)
            errorMessage = "Pocket TTS local runtime currently supports English text only."
            markRequestFinished()
            return
        }

        logger.info(
            "TTS provider: \(ttsConfiguration.provider.rawValue), voice: \(ttsConfiguration.historyVoiceLabel)",
            source: logSource
        )

        if summarizationPromptOverride != nil && !shouldSummarize {
            logger.warning("Prompt override ignored because summarize=false", source: logSource)
        }

        // Route to appropriate pipeline based on options
        if shouldSummarize && language != .none {
            guard let openAIAPIKey else {
                logger.error("OpenAI API key missing for summarize+translate flow", source: logSource)
                errorMessage = "No OpenAI API key configured. Enter key in Settings or set OPENAI_API_KEY."
                markRequestFinished()
                return
            }
            // Summarize + Translate + TTS (interleaved pipeline)
            await processSummarizeTranslateTTS(
                text: text,
                openAIAPIKey: openAIAPIKey,
                ttsConfiguration: ttsConfiguration,
                language: language,
                summarizationPrompt: summarizationPromptToUse,
                logSource: logSource
            )
        } else if shouldSummarize {
            guard let openAIAPIKey else {
                logger.error("OpenAI API key missing for summarize flow", source: logSource)
                errorMessage = "No OpenAI API key configured. Enter key in Settings or set OPENAI_API_KEY."
                markRequestFinished()
                return
            }
            // Summarize + TTS
            await processSummarizeTTS(
                text: text,
                openAIAPIKey: openAIAPIKey,
                ttsConfiguration: ttsConfiguration,
                summarizationPrompt: summarizationPromptToUse,
                logSource: logSource
            )
        } else if language != .none {
            guard let openAIAPIKey else {
                logger.error("OpenAI API key missing for translate flow", source: logSource)
                errorMessage = "No OpenAI API key configured. Enter key in Settings or set OPENAI_API_KEY."
                markRequestFinished()
                return
            }
            // Translate + TTS
            await processTranslateTTS(
                text: text,
                openAIAPIKey: openAIAPIKey,
                ttsConfiguration: ttsConfiguration,
                language: language,
                logSource: logSource
            )
        } else {
            // Direct TTS
            await processDirectTTS(
                text: text,
                ttsConfiguration: ttsConfiguration,
                logSource: logSource
            )
        }
    }

    /// Direct TTS from queued request (no summarization or translation)
    @MainActor
    private func processDirectTTS(
        text: String,
        ttsConfiguration: TTSConfiguration,
        logSource: String
    ) async {
        logger.info("Direct TTS starting", source: logSource)

        isLoading = true
        errorMessage = nil

        currentText = text
        displayText = text

        // Reset tracking state
        resetAccumulatedAudioData()
        pendingHistorySave = nil
        historySaved = false

        // Reset audio player
        audioPlayer.reset()
        audioPlayer.playbackSpeed = Float(playbackSpeed)
        audioPlayer.setEstimatedDuration(forTextLength: text.count)

        // Store pending history info
        pendingHistorySave = (
            text: text,
            voice: ttsConfiguration.historyVoiceLabel,
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
            self?.logger.info("Audio playback complete", source: logSource)
            Task { @MainActor in
                self?.handlePlaybackComplete()
            }
        }

        // Start playback
        isPlaying = true
        isLoading = false
        audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)
        startProgressTracking()

        // Start streaming TTS
        ttsService.streamSpeech(
            text: text,
            configuration: ttsConfiguration,
            onAudioChunk: { [weak self] data in
                guard let self = self else { return }
                self.audioPlayer.enqueue(pcmData: data)
                Task { @MainActor in
                    self.appendAccumulatedAudioData(data)
                }
            },
            onComplete: { [weak self] result in
                self?.logger.info("TTS stream complete, inputTokens: \(result.inputTokens)", source: logSource)
                if var pending = self?.pendingHistorySave {
                    pending.inputTokens = result.inputTokens
                    self?.pendingHistorySave = pending
                }
                self?.audioPlayer.markStreamComplete()
            },
            onError: { [weak self] error in
                self?.logger.error("TTS error: \(error.localizedDescription)", source: logSource)
                Task { @MainActor in
                    self?.errorMessage = error.localizedDescription
                    self?.isLoading = false
                    self?.isPlaying = false
                    self?.stopProgressTracking()
                    self?.audioLevelMonitor.stopMonitoring()
                    self?.markRequestFinished()
                }
            }
        )
    }

    /// Summarize + TTS from queued request
    @MainActor
    private func processSummarizeTTS(
        text: String,
        openAIAPIKey: String,
        ttsConfiguration: TTSConfiguration,
        summarizationPrompt: String,
        logSource: String
    ) async {
        logger.info("Summarize+TTS starting", source: logSource)

        isLoading = true
        isSummarizing = true
        errorMessage = nil

        // Reset state
        streamingSummary = ""
        resetAccumulatedAudioData()
        pendingHistorySave = nil
        historySaved = false

        // Reset audio player
        audioPlayer.reset()
        audioPlayer.playbackSpeed = Float(playbackSpeed)
        audioPlayer.setEstimatedDuration(forTextLength: text.count / 3)

        let model = LLMModel(rawValue: summarizationModel) ?? .gpt5Nano

        // Configure interleaved pipeline for summarize-only
        interleavedPipeline.onSummarySentence = { [weak self] sentence in
            guard let self = self else { return }
            self.streamingSummary += sentence + " "
            self.displayText = self.streamingSummary.trimmingCharacters(in: .whitespaces)
        }

        interleavedPipeline.onTranslatedSentence = { _ in }

        interleavedPipeline.onAudioChunk = { [weak self] data in
            guard let self = self else { return }
            self.audioPlayer.enqueue(pcmData: data)
            Task { @MainActor in
                self.appendAccumulatedAudioData(data)
            }
        }

        interleavedPipeline.onProgress = { [weak self] status in
            self?.logger.debug("Pipeline progress: \(status)", source: logSource)
        }

        interleavedPipeline.onComplete = { [weak self] result in
            guard let self = self else { return }
            self.logger.info("Summarize pipeline complete", source: logSource)

            self.displayText = result.summarizedText
            self.currentText = result.summarizedText

            self.pendingHistorySave = (
                text: text,
                voice: ttsConfiguration.historyVoiceLabel,
                inputTokens: result.ttsInputTokens,
                summarizedText: result.summarizedText,
                llmInputTokens: result.summarizationInputTokens,
                llmOutputTokens: result.summarizationOutputTokens,
                llmModel: result.summarizationModel,
                translatedText: nil,
                translationInputTokens: nil,
                translationOutputTokens: nil,
                translationModel: nil,
                targetLanguage: nil
            )

            self.isSummarizing = false
            self.audioPlayer.markStreamComplete()
        }

        interleavedPipeline.onError = { [weak self] error in
            guard let self = self else { return }
            self.logger.error("Pipeline error: \(error.localizedDescription)", source: logSource)
            self.errorMessage = error.localizedDescription
            self.isLoading = false
            self.isPlaying = false
            self.isSummarizing = false
            self.stopProgressTracking()
            self.audioLevelMonitor.stopMonitoring()
            self.markRequestFinished()
        }

        audioPlayer.onPlaybackComplete = { [weak self] in
            self?.logger.info("Audio playback complete", source: logSource)
            Task { @MainActor in
                self?.handlePlaybackComplete()
            }
        }

        isPlaying = true
        isLoading = false
        audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)
        startProgressTracking()

        let config = InterleavedPipelineConfig(
            openAIAPIKey: openAIAPIKey,
            summarizationModel: model,
            summarizationPrompt: summarizationPrompt,
            targetLanguage: .none,
            translationModel: model,
            translationPrompt: "",
            ttsConfiguration: ttsConfiguration
        )

        interleavedPipeline.start(text: text, config: config)
    }

    /// Translate + TTS from queued request (no summarization)
    @MainActor
    private func processTranslateTTS(
        text: String,
        openAIAPIKey: String,
        ttsConfiguration: TTSConfiguration,
        language: TargetLanguage,
        logSource: String
    ) async {
        logger.info("Translate+TTS starting for language: \(language.rawValue)", source: logSource)

        isLoading = true
        isTranslating = true
        errorMessage = nil

        // Reset state
        streamingTranslation = ""
        resetAccumulatedAudioData()
        pendingHistorySave = nil
        historySaved = false

        // Reset audio player
        audioPlayer.reset()
        audioPlayer.playbackSpeed = Float(playbackSpeed)
        audioPlayer.setEstimatedDuration(forTextLength: text.count)

        let translationModel = LLMModel(rawValue: translationModelSetting) ?? .gpt5Nano

        // For translate-only, we use LLMService directly
        do {
            let translatedText = try await llmService.translateSentence(
                sentence: text,
                context: nil,
                targetLanguage: language,
                model: translationModel,
                systemPrompt: translationPrompt(for: language),
                apiKey: openAIAPIKey
            )

            displayText = translatedText
            currentText = translatedText

            pendingHistorySave = (
                text: text,
                voice: ttsConfiguration.historyVoiceLabel,
                inputTokens: 0,
                summarizedText: nil,
                llmInputTokens: nil,
                llmOutputTokens: nil,
                llmModel: nil,
                translatedText: translatedText,
                translationInputTokens: nil,
                translationOutputTokens: nil,
                translationModel: translationModel.rawValue,
                targetLanguage: language.rawValue
            )

            audioPlayer.onPlaybackComplete = { [weak self] in
                self?.logger.info("Audio playback complete", source: logSource)
                Task { @MainActor in
                    self?.handlePlaybackComplete()
                }
            }

            isPlaying = true
            isLoading = false
            isTranslating = false
            audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)
            startProgressTracking()

            // Stream TTS for translated text
            ttsService.streamSpeech(
                text: translatedText,
                configuration: ttsConfiguration,
                onAudioChunk: { [weak self] data in
                    guard let self = self else { return }
                    self.audioPlayer.enqueue(pcmData: data)
                    Task { @MainActor in
                        self.appendAccumulatedAudioData(data)
                    }
                },
                onComplete: { [weak self] result in
                    self?.logger.info("TTS stream complete, inputTokens: \(result.inputTokens)", source: logSource)
                    if var pending = self?.pendingHistorySave {
                        pending.inputTokens = result.inputTokens
                        self?.pendingHistorySave = pending
                    }
                    self?.audioPlayer.markStreamComplete()
                },
                onError: { [weak self] error in
                    self?.logger.error("TTS error: \(error.localizedDescription)", source: logSource)
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                        self?.isPlaying = false
                        self?.isTranslating = false
                        self?.stopProgressTracking()
                        self?.audioLevelMonitor.stopMonitoring()
                        self?.markRequestFinished()
                    }
                }
            )
        } catch {
            logger.error("Translation error: \(error.localizedDescription)", source: logSource)
            errorMessage = error.localizedDescription
            isLoading = false
            isTranslating = false
            markRequestFinished()
        }
    }

    /// Summarize + Translate + TTS from queued request (full interleaved pipeline)
    @MainActor
    private func processSummarizeTranslateTTS(
        text: String,
        openAIAPIKey: String,
        ttsConfiguration: TTSConfiguration,
        language: TargetLanguage,
        summarizationPrompt: String,
        logSource: String
    ) async {
        logger.info("Summarize+Translate+TTS starting for language: \(language.rawValue)", source: logSource)

        isLoading = true
        isTranslating = true  // Show translation UI since that's the final output
        errorMessage = nil

        // Reset state
        streamingSummary = ""
        streamingTranslation = ""
        resetAccumulatedAudioData()
        pendingHistorySave = nil
        historySaved = false

        // Reset audio player
        audioPlayer.reset()
        audioPlayer.playbackSpeed = Float(playbackSpeed)
        audioPlayer.setEstimatedDuration(forTextLength: text.count / 3)

        let model = LLMModel(rawValue: summarizationModel) ?? .gpt5Nano
        let translationModel = LLMModel(rawValue: translationModelSetting) ?? .gpt5Nano

        // Configure interleaved pipeline callbacks
        interleavedPipeline.onSummarySentence = { _ in }  // Don't show summary when translating

        interleavedPipeline.onTranslatedSentence = { [weak self] sentence in
            guard let self = self else { return }
            self.streamingTranslation += sentence + " "
            self.displayText = self.streamingTranslation.trimmingCharacters(in: .whitespaces)
        }

        interleavedPipeline.onAudioChunk = { [weak self] data in
            guard let self = self else { return }
            self.audioPlayer.enqueue(pcmData: data)
            Task { @MainActor in
                self.appendAccumulatedAudioData(data)
            }
        }

        interleavedPipeline.onProgress = { [weak self] status in
            self?.logger.debug("Pipeline progress: \(status)", source: logSource)
        }

        interleavedPipeline.onComplete = { [weak self] result in
            guard let self = self else { return }
            self.logger.info("Interleaved pipeline complete", source: logSource)

            let finalText = result.translatedText ?? result.summarizedText
            self.displayText = finalText
            self.currentText = finalText

            self.pendingHistorySave = (
                text: text,
                voice: ttsConfiguration.historyVoiceLabel,
                inputTokens: result.ttsInputTokens,
                summarizedText: result.summarizedText,
                llmInputTokens: result.summarizationInputTokens,
                llmOutputTokens: result.summarizationOutputTokens,
                llmModel: result.summarizationModel,
                translatedText: result.translatedText,
                translationInputTokens: result.translationInputTokens,
                translationOutputTokens: result.translationOutputTokens,
                translationModel: result.translationModel,
                targetLanguage: language.rawValue
            )

            self.isSummarizing = false
            self.isTranslating = false
            self.audioPlayer.markStreamComplete()
        }

        interleavedPipeline.onError = { [weak self] error in
            guard let self = self else { return }
            self.logger.error("Pipeline error: \(error.localizedDescription)", source: logSource)
            self.errorMessage = error.localizedDescription
            self.isLoading = false
            self.isPlaying = false
            self.isSummarizing = false
            self.isTranslating = false
            self.stopProgressTracking()
            self.audioLevelMonitor.stopMonitoring()
            self.markRequestFinished()
        }

        audioPlayer.onPlaybackComplete = { [weak self] in
            self?.logger.info("Audio playback complete", source: logSource)
            Task { @MainActor in
                self?.handlePlaybackComplete()
            }
        }

        isPlaying = true
        isLoading = false
        audioLevelMonitor.startMonitoring(engine: audioPlayer.audioEngine)
        startProgressTracking()

        let config = InterleavedPipelineConfig(
            openAIAPIKey: openAIAPIKey,
            summarizationModel: model,
            summarizationPrompt: summarizationPrompt,
            targetLanguage: language,
            translationModel: translationModel,
            translationPrompt: translationPrompt(for: language),
            ttsConfiguration: ttsConfiguration
        )

        interleavedPipeline.start(text: text, config: config)
    }
}
