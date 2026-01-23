import SwiftUI
import KeyboardShortcuts

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentText: String?
    @Published var errorMessage: String?

    @AppStorage("selectedVoice") var selectedVoice: String = TTSVoice.coral.rawValue
    @AppStorage("openaiAPIKey") var apiKey: String = ""

    // Audio level monitor for waveform visualization
    let audioLevelMonitor = AudioLevelMonitor()

    private let ttsService = TTSService()
    private let audioPlayer = StreamingAudioPlayer.shared
    private let accessibilityManager = AccessibilityManager.shared

    private let logger = DebugLogger.shared

    // Track state for history save on stop
    private var accumulatedAudioData = Data()
    private var pendingHistorySave: (text: String, voice: String, inputTokens: Int)?
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

            // Reset audio player for fresh playback
            audioPlayer.reset()

            // Get the voice enum from stored string
            let voice = TTSVoice(rawValue: selectedVoice) ?? .coral
            logger.info("Using voice: \(voice.rawValue)", source: "AppState")

            // Store pending history info for save on stop
            pendingHistorySave = (text: text, voice: voice.rawValue, inputTokens: 0)

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

    func stopPlayback() {
        logger.info("Stopping playback", source: "AppState")

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
                audioData: accumulatedAudioData
            )
            historySaved = true
        }

        // Clear state
        isPlaying = false
        currentText = nil
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
                audioData: accumulatedAudioData
            )
            historySaved = true
        }

        // Stop monitoring and clear state
        audioLevelMonitor.stopMonitoring()
        isPlaying = false
        currentText = nil
        accumulatedAudioData = Data()
        pendingHistorySave = nil
    }
}
