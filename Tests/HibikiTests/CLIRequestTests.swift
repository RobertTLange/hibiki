import XCTest
import HibikiCLICore

final class CLIRequestTests: XCTestCase {
    func testPromptIncludedWhenSummarizeEnabled() throws {
        let request = CLIRequest(
            text: "Hello world",
            summarize: true,
            translate: nil,
            prompt: "Summarize in one sentence."
        )

        let url = try request.url()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertEqual(queryItems.first(where: { $0.name == "summarize" })?.value, "true")
        XCTAssertEqual(queryItems.first(where: { $0.name == "prompt" })?.value, "Summarize in one sentence.")
    }

    func testPromptOmittedWhenNil() throws {
        let request = CLIRequest(text: "Hello world", summarize: true, translate: nil, prompt: nil)

        let url = try request.url()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        XCTAssertNil(queryItems.first(where: { $0.name == "prompt" }))
    }

    func testPromptRequiresSummarize() {
        let request = CLIRequest(text: "Hello world", summarize: false, translate: nil, prompt: "Short")

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? CLIRequestError, .promptWithoutSummarize)
        }
    }

    func testPromptCannotBeEmpty() {
        let request = CLIRequest(text: "Hello world", summarize: true, translate: nil, prompt: "  ")

        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? CLIRequestError, .emptyPrompt)
        }
    }
}
