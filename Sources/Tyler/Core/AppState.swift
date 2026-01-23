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

    private let ttsService = TTSService()
    private let audioPlayer = StreamingAudioPlayer.shared
    private let accessibilityManager = AccessibilityManager.shared

    private let logger = DebugLogger.shared

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

            // Reset audio player for fresh playback
            audioPlayer.reset()

            // Get the voice enum from stored string
            let voice = TTSVoice(rawValue: selectedVoice) ?? .coral
            logger.info("Using voice: \(voice.rawValue)", source: "AppState")

            // Start streaming TTS
            logger.info("Starting TTS stream...", source: "AppState")
            ttsService.streamSpeech(
                text: text,
                voice: voice,
                apiKey: effectiveApiKey,
                onAudioChunk: { [weak self] data in
                    self?.logger.debug("Received audio chunk: \(data.count) bytes", source: "AppState")
                    self?.audioPlayer.enqueue(pcmData: data)
                },
                onComplete: { [weak self] result in
                    self?.logger.info("TTS stream complete, audio size: \(result.audioData.count) bytes, inputTokens: \(result.inputTokens)", source: "AppState")

                    // Save to history
                    HistoryManager.shared.addEntry(
                        text: text,
                        voice: voice.rawValue,
                        inputTokens: result.inputTokens,
                        audioData: result.audioData
                    )
                    self?.logger.info("Saved to history", source: "AppState")

                    Task { @MainActor in
                        // Small delay to let audio finish playing
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self?.isPlaying = false
                        self?.currentText = nil
                    }
                },
                onError: { [weak self] error in
                    self?.logger.error("TTS error: \(error.localizedDescription)", source: "AppState")
                    Task { @MainActor in
                        self?.errorMessage = error.localizedDescription
                        self?.isLoading = false
                        self?.isPlaying = false
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
        audioPlayer.stop()
        ttsService.cancel()
        isPlaying = false
        currentText = nil
    }
}
