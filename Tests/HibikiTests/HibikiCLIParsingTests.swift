import XCTest
@testable import HibikiCLI

final class HibikiCLIParsingTests: XCTestCase {
    /// Regression: `--text "- Fixed the bug"` failed with "Missing value for '--text'",
    /// so the agent hook said nothing for any message starting with a bullet.
    func testTextMayStartWithADash() throws {
        let command = try HibikiCLI.parse(["--text", "- Fixed the bug"])
        XCTAssertEqual(command.text, "- Fixed the bug")
    }

    func testTextThatLooksLikeAFlagIsStillText() throws {
        let command = try HibikiCLI.parse(["--text", "--summarize is a flag", "--summarize"])
        XCTAssertEqual(command.text, "--summarize is a flag")
        XCTAssertTrue(command.summarize)
    }

    func testPromptMayStartWithADash() throws {
        let command = try HibikiCLI.parse(["--text", "Hello", "--summarize", "--prompt", "- three bullets"])
        XCTAssertEqual(command.prompt, "- three bullets")
    }

    func testEqualsFormStillWorks() throws {
        let command = try HibikiCLI.parse(["--text=-dash", "--translate", "ja"])
        XCTAssertEqual(command.text, "-dash")
        XCTAssertEqual(command.translate, "ja")
    }

    func testMissingInputIsRejected() {
        XCTAssertThrowsError(try HibikiCLI.parse(["--summarize"]))
    }
}
