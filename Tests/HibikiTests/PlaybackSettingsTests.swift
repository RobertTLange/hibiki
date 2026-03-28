import XCTest
import HibikiShared

final class PlaybackSettingsTests: XCTestCase {
    func testSpeedLabelUsesSingleDecimalPlace() {
        XCTAssertEqual(PlaybackSettings.speedLabel(for: 1.0), "1.0x")
        XCTAssertEqual(PlaybackSettings.speedLabel(for: 2.45), "2.5x")
    }

    func testClampedSpeedKeepsValueInsideSupportedRange() {
        XCTAssertEqual(PlaybackSettings.clampedSpeed(0.2), 1.0)
        XCTAssertEqual(PlaybackSettings.clampedSpeed(1.7), 1.7)
        XCTAssertEqual(PlaybackSettings.clampedSpeed(3.1), 2.5)
    }

    func testClampedVolumeKeepsValueInsideSupportedRange() {
        XCTAssertEqual(PlaybackSettings.clampedVolume(-1.0), 0.0)
        XCTAssertEqual(PlaybackSettings.clampedVolume(1.25), 1.25)
        XCTAssertEqual(PlaybackSettings.clampedVolume(4.0, maxVolume: 3.0), 3.0)
    }
}
