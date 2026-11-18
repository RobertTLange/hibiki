import XCTest
@testable import Hibiki

final class StreamingAudioPlayerTests: XCTestCase {
    private let player = StreamingAudioPlayer.shared

    override func tearDown() {
        player.onPlaybackComplete = nil
        player.stop()
        super.tearDown()
    }

    /// Regression: a stream that ended without any audio (whitespace-only text, empty
    /// provider response) never reported completion, leaving the app stuck "playing".
    func testStreamWithoutAudioStillCompletes() {
        let completed = expectation(description: "playback complete")
        player.reset()
        player.onPlaybackComplete = { completed.fulfill() }

        player.markStreamComplete()

        wait(for: [completed], timeout: 2)
        XCTAssertFalse(player.audioEngine.isRunning)
    }

    /// Regression: a chunk arriving after stop() restarted the engine and kept playing.
    func testAudioArrivingAfterStopIsDropped() {
        let completed = expectation(description: "no completion for dropped audio")
        completed.isInverted = true
        player.reset()
        player.onPlaybackComplete = { completed.fulfill() }
        player.stop()

        player.enqueue(pcmData: Data(count: 24_000))  // 0.5s, above the start threshold
        player.markStreamComplete()

        wait(for: [completed], timeout: 0.5)
        XCTAssertFalse(player.audioEngine.isRunning)
    }

    func testPlaybackCompletesAfterScheduledAudio() {
        let completed = expectation(description: "playback complete")
        player.reset()
        player.onPlaybackComplete = { completed.fulfill() }

        player.enqueue(pcmData: Data(count: 14_400))  // 0.3s of silence
        player.markStreamComplete()

        wait(for: [completed], timeout: 5)
    }
}
