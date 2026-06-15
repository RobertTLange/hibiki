import XCTest
import HibikiShared

final class MistralLocalConfigurationTests: XCTestCase {
    func testMistralLocalDefaultBaseURLMatchesManagedServerPort() {
        let configuration = makeConfiguration()

        XCTAssertEqual(configuration.normalizedBaseURL, "http://127.0.0.1:8091")
        XCTAssertEqual(
            configuration.speechURL?.absoluteString,
            "http://127.0.0.1:8091/v1/audio/speech"
        )
    }

    func testMistralLocalBaseURLDefaultsToOpenAICompatibleSpeechEndpoint() {
        let configuration = makeConfiguration(mistralLocalBaseURL: "127.0.0.1:9999")

        XCTAssertEqual(configuration.normalizedBaseURL, "http://127.0.0.1:9999")
        XCTAssertEqual(
            configuration.speechURL?.absoluteString,
            "http://127.0.0.1:9999/v1/audio/speech"
        )
    }

    func testMistralLocalFallsBackToDefaultModelAndVoice() {
        let configuration = makeConfiguration(
            mistralLocalModelID: "   ",
            mistralLocalVoice: ""
        )

        XCTAssertEqual(
            configuration.normalizedModelID,
            MistralLocalTTSDefaults.modelID
        )
        XCTAssertEqual(
            configuration.normalizedVoice,
            MistralLocalTTSDefaults.voice
        )
        XCTAssertEqual(configuration.historyVoiceLabel, "mistral:\(MistralLocalTTSDefaults.voice)")
    }

    func testMistralLocalVoiceLabelsAreClassifiedAsFreeLocalAudio() {
        XCTAssertTrue(LocalTTSVoiceLabel.isLocal("mistral:casual_male"))
        XCTAssertTrue(LocalTTSVoiceLabel.isMistral("mistral:casual_male"))
        XCTAssertFalse(LocalTTSVoiceLabel.isMistral("pocket:alba"))
    }

    private func makeConfiguration(
        mistralLocalBaseURL: String = "",
        mistralLocalModelID: String = MistralLocalTTSDefaults.modelID,
        mistralLocalVoice: String = MistralLocalTTSDefaults.voice
    ) -> MistralLocalTTSConfiguration {
        MistralLocalTTSConfiguration(
            mistralLocalBaseURL: mistralLocalBaseURL,
            mistralLocalModelID: mistralLocalModelID,
            mistralLocalVoice: mistralLocalVoice
        )
    }
}
