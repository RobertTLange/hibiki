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

    private func installStubs(ttsDelay: TimeInterval) {
        let chat = StubResponses.chatStream(sentences: sentences)
        StubURLProtocol.install { request in
            if request.url?.path.hasSuffix("/chat/completions") == true {
                return .init(body: chat)
            }
            return .init(body: StubResponses.pcm(seconds: 0.2), delay: ttsDelay)
        }
    }

    private func makeConfig() -> InterleavedPipelineConfig {
        InterleavedPipelineConfig(
            openAIAPIKey: "test-key",
            summarizationModel: .defaultModel,
            summarizationPrompt: "Summarize.",
            targetLanguage: .none,
            translationModel: .defaultModel,
            translationPrompt: "",
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
        for _ in 0..<100 where StubURLProtocol.requestCount(pathSuffix: "/audio/speech") == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(audioChunks, 0)
        pipeline.cancel()

        pipeline.onComplete = { _ in completed.fulfill() }
        pipeline.start(text: "Second request.", config: makeConfig())
        await fulfillment(of: [completed], timeout: 10)

        // Let anything stale from the first run arrive.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(audioChunks, 3, "only the second run's three sentences may be delivered")
    }

    func testCancelledRunDeliversNothingFurther() async throws {
        installStubs(ttsDelay: 0.2)

        let pipeline = InterleavedPipeline()
        var audioChunks = 0
        pipeline.onAudioChunk = { _ in audioChunks += 1 }
        pipeline.onComplete = { _ in XCTFail("cancelled run must not complete") }
        pipeline.onError = { error in XCTFail("cancellation must not surface as an error: \(error)") }

        pipeline.start(text: "Request.", config: makeConfig())
        for _ in 0..<200 where audioChunks == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(audioChunks, 1)
        pipeline.cancel()

        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(audioChunks, 1)
    }
}
