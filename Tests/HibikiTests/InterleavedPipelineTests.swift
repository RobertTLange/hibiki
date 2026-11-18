import XCTest
@testable import Hibiki
import HibikiShared

@MainActor
final class InterleavedPipelineTests: XCTestCase {
    private let sentences = [
        "The first sentence is long enough to be emitted. ",
        "The second sentence follows right after the first. ",
        "The third sentence closes out the short summary."
    ]

    private var expectedTTSTokens: Int {
        sentences
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(0) { $0 + max(1, $1.count / 4) }
    }

    override func tearDown() async throws {
        StubURLProtocol.uninstall()
    }

    private static let translationMarker = "TRANSLATE-THIS-MARKER"

    /// Summaries answer at once; translations (recognised by their system prompt) and TTS
    /// requests answer after the given delays.
    private func installStubs(ttsDelay: TimeInterval, translationDelay: TimeInterval = 0) {
        let chat = StubResponses.chatStream(sentences: sentences)
        let translation = StubResponses.chatStream(sentences: ["Ein übersetzter Satz, lang genug."])
        StubURLProtocol.install { request in
            if request.url?.path.hasSuffix("/chat/completions") == true {
                let body = String(data: StubURLProtocol.body(of: request), encoding: .utf8) ?? ""
                if body.contains(Self.translationMarker) {
                    return .init(body: translation, delay: translationDelay)
                }
                return .init(body: chat)
            }
            return .init(body: StubResponses.pcm(seconds: 0.2), delay: ttsDelay)
        }
    }

    private func makeConfig(translatingTo targetLanguage: TargetLanguage = .none) -> InterleavedPipelineConfig {
        InterleavedPipelineConfig(
            openAIAPIKey: "test-key",
            summarizationModel: .defaultModel,
            summarizationPrompt: "Summarize.",
            targetLanguage: targetLanguage,
            translationModel: .defaultModel,
            translationPrompt: Self.translationMarker,
            ttsConfiguration: TTSConfiguration(
                provider: .openAI,
                openAIAPIKey: "test-key",
                openAIVoice: .coral,
                elevenLabsAPIKey: "",
                elevenLabsVoiceID: "",
                elevenLabsModelID: TTSConfiguration.defaultElevenLabsModelID,
                pocketBaseURL: TTSConfiguration.defaultPocketBaseURL,
                pocketVoiceURL: TTSConfiguration.defaultPocketVoiceURL,
                pocketRequestTimeoutSec: TTSConfiguration.defaultPocketRequestTimeoutSec,
                instructions: TTSConfiguration.defaultInstructions
            )
        )
    }

    /// Regression: completion used to fire 0.5s after the LLM stream ended, while sentences
    /// were still being synthesized. Playback was then marked finished mid-summary and the
    /// TTS token count missed every sentence still in the queue.
    func testCompletionWaitsForEverySentenceToBeSynthesized() async {
        // 3 sentences x 0.4s each: well past the old 0.5s grace period.
        installStubs(ttsDelay: 0.4)

        let pipeline = InterleavedPipeline()
        var events: [String] = []
        var completedResult: InterleavedPipelineResult?
        let completed = expectation(description: "pipeline complete")

        pipeline.onAudioChunk = { _ in events.append("audio") }
        pipeline.onTextComplete = { _ in events.append("text") }
        pipeline.onComplete = { result in
            events.append("complete")
            completedResult = result
            completed.fulfill()
        }
        pipeline.onError = { error in XCTFail("unexpected pipeline error: \(error)") }

        pipeline.start(text: "Some long source text.", config: makeConfig())
        await fulfillment(of: [completed], timeout: 10)

        XCTAssertEqual(events.filter { $0 == "audio" }.count, 3)
        XCTAssertEqual(events.last, "complete", "completion must come after the last audio chunk")
        XCTAssertEqual(events.filter { $0 == "complete" }.count, 1)
        XCTAssertLessThan(events.firstIndex(of: "text") ?? .max, events.count - 1)
        XCTAssertEqual(completedResult?.ttsInputTokens, expectedTTSTokens)
        XCTAssertEqual(completedResult?.summarizationInputTokens, 100)
        XCTAssertEqual(completedResult?.summarizationOutputTokens, 40)
        XCTAssertEqual(
            completedResult?.summarizedText,
            sentences.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        )
    }

    /// Regression: sentence requests were not tied to a run, so audio for a cancelled
    /// summary was delivered into (and saved with) the next one.
    func testAudioFromCancelledRunDoesNotLeakIntoNextRun() async throws {
        installStubs(ttsDelay: 0.3)

        let pipeline = InterleavedPipeline()
        var audioChunks = 0
        let completed = expectation(description: "second run complete")

        pipeline.onAudioChunk = { _ in audioChunks += 1 }
        pipeline.onError = { error in XCTFail("unexpected pipeline error: \(error)") }

        // First run: wait until its first TTS request is in flight, then cancel.
        pipeline.onComplete = { _ in XCTFail("cancelled run must not complete") }
        pipeline.start(text: "First request.", config: makeConfig())
        for _ in 0..<300 where StubURLProtocol.requestCount(pathSuffix: "/audio/speech") == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(StubURLProtocol.requestCount(pathSuffix: "/audio/speech"), 0)
        pipeline.cancel()
        let chunksFromFirstRun = audioChunks

        pipeline.onComplete = { _ in completed.fulfill() }
        pipeline.start(text: "Second request.", config: makeConfig())
        await fulfillment(of: [completed], timeout: 10)

        // Let anything stale from the first run arrive.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(
            audioChunks - chunksFromFirstRun, 3,
            "only the second run's three sentences may be delivered after the first was cancelled"
        )
    }

    func testCancelledRunDeliversNothingFurther() async throws {
        installStubs(ttsDelay: 0.2)

        let pipeline = InterleavedPipeline()
        var audioChunks = 0
        pipeline.onAudioChunk = { _ in audioChunks += 1 }
        pipeline.onComplete = { _ in XCTFail("cancelled run must not complete") }
        pipeline.onError = { error in XCTFail("cancellation must not surface as an error: \(error)") }

        pipeline.start(text: "Request.", config: makeConfig())
        for _ in 0..<500 where audioChunks == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(audioChunks, 0)
        pipeline.cancel()
        let chunksAtCancel = audioChunks
        XCTAssertLessThan(chunksAtCancel, 3, "cancel must land before the run is finished")

        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(audioChunks, chunksAtCancel)
    }

    // MARK: - Summarize + translate

    func testTranslatedRunSpeaksTheTranslations() async {
        installStubs(ttsDelay: 0.05, translationDelay: 0.05)

        let pipeline = InterleavedPipeline()
        var translated: [String] = []
        var completedResult: InterleavedPipelineResult?
        let completed = expectation(description: "pipeline complete")

        pipeline.onTranslatedSentence = { translated.append($0) }
        pipeline.onComplete = { result in
            completedResult = result
            completed.fulfill()
        }
        pipeline.onError = { error in XCTFail("unexpected pipeline error: \(error)") }

        pipeline.start(text: "Source text.", config: makeConfig(translatingTo: .german))
        await fulfillment(of: [completed], timeout: 10)

        XCTAssertEqual(translated.count, 3)
        XCTAssertEqual(completedResult?.translatedText, Array(repeating: "Ein übersetzter Satz, lang genug.", count: 3).joined(separator: " "))
        XCTAssertGreaterThan(completedResult?.translationInputTokens ?? 0, 0)
        XCTAssertEqual(StubURLProtocol.requestCount(pathSuffix: "/audio/speech"), 3)
    }

    /// Regression: per-sentence translation runs in tasks that stopping does not cancel. A run
    /// stopped while its last sentences were translating still delivered its text result
    /// afterwards, over whatever was playing by then.
    func testRunStoppedDuringTranslationDeliversNothingAfterwards() async throws {
        installStubs(ttsDelay: 0.05, translationDelay: 0.4)

        let pipeline = InterleavedPipeline()
        var translatedAfterCancel = 0
        var isCancelled = false
        pipeline.onTranslatedSentence = { _ in if isCancelled { translatedAfterCancel += 1 } }
        pipeline.onTextComplete = { _ in XCTFail("a stopped run must not deliver its text result") }
        pipeline.onComplete = { _ in XCTFail("a stopped run must not complete") }
        pipeline.onError = { error in XCTFail("stopping must not surface as an error: \(error)") }

        pipeline.start(text: "Source text.", config: makeConfig(translatingTo: .german))
        // The summary arrives at once; three translations of 0.4s each follow one by one.
        try await Task.sleep(nanoseconds: 600_000_000)
        pipeline.cancel()
        isCancelled = true

        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(translatedAfterCancel, 0)
    }

    /// Regression: a translation still in flight when its run was stopped came back into the
    /// next run (whose start resets the cancelled flag) and was spoken there.
    func testLateTranslationFromStoppedRunDoesNotJoinTheNextRun() async throws {
        installStubs(ttsDelay: 0.05, translationDelay: 0.4)

        let pipeline = InterleavedPipeline()
        var translatedSentences = 0
        var completedResult: InterleavedPipelineResult?
        let completed = expectation(description: "second run complete")

        pipeline.onTranslatedSentence = { _ in translatedSentences += 1 }
        pipeline.onError = { error in XCTFail("unexpected pipeline error: \(error)") }
        pipeline.onComplete = { _ in XCTFail("the stopped run must not complete") }

        pipeline.start(text: "First request.", config: makeConfig(translatingTo: .german))
        try await Task.sleep(nanoseconds: 200_000_000)  // first translation is in flight
        pipeline.cancel()
        let translatedBeforeSecondRun = translatedSentences

        // Second run: summary only, so any translated sentence can only come from the first.
        let audioRequestsBefore = StubURLProtocol.requestCount(pathSuffix: "/audio/speech")
        pipeline.onComplete = { result in
            completedResult = result
            completed.fulfill()
        }
        pipeline.start(text: "Second request.", config: makeConfig())
        await fulfillment(of: [completed], timeout: 10)
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(translatedSentences, translatedBeforeSecondRun)
        XCTAssertNil(completedResult?.translatedText)
        XCTAssertEqual(
            completedResult?.summarizedText,
            sentences.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        )
        XCTAssertEqual(StubURLProtocol.requestCount(pathSuffix: "/audio/speech") - audioRequestsBefore, 3)
    }
}
