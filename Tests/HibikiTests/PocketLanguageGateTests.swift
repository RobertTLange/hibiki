import XCTest
@testable import Hibiki
import HibikiPocketRuntime

final class PocketLanguageGateTests: XCTestCase {
    private let german = "Dies ist ein längerer deutscher Text, der vorgelesen werden soll, und zwar vollständig."
    private let english = "This is a longer English text that should be read aloud from start to finish."

    func testEnglishSourceWithoutTranslationIsAllowed() {
        XCTAssertTrue(AppState.pocketCanSpeak(sourceText: english, translatingTo: .none))
    }

    func testForeignSourceWithoutTranslationIsRejected() {
        XCTAssertFalse(AppState.pocketCanSpeak(sourceText: german, translatingTo: .none))
    }

    /// Regression: the gate looked at the source text, so German translated *to* English
    /// was refused while English translated to Japanese was sent to the English-only model.
    func testGateFollowsTheSpokenLanguageWhenTranslating() {
        XCTAssertTrue(AppState.pocketCanSpeak(sourceText: german, translatingTo: .english))
        XCTAssertFalse(AppState.pocketCanSpeak(sourceText: english, translatingTo: .japanese))
        XCTAssertFalse(AppState.pocketCanSpeak(sourceText: english, translatingTo: .german))
    }

    func testVeryShortTextIsNotGuessedAt() {
        XCTAssertTrue(AppState.pocketCanSpeak(sourceText: "Hallo", translatingTo: .none))
    }

    func testLoopbackHosts() {
        for host in ["127.0.0.1", "localhost", " LOCALHOST ", "::1"] {
            XCTAssertTrue(PocketTTSRuntimeManager.isLoopbackHost(host), host)
        }
        for host in ["192.168.1.20", "example.com", "0.0.0.0", ""] {
            XCTAssertFalse(PocketTTSRuntimeManager.isLoopbackHost(host), host)
        }
    }
}
