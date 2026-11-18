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

    // MARK: - URL round trip (CLI -> app)

    func testURLRoundTripPreservesAwkwardText() throws {
        let text = "- a&b=c+d #frag ? 100% \"quoted\"\nline two é 日本語 🎧"
        let sent = CLIRequest(text: text, summarize: true, translate: "JA", prompt: "- three bullets & no more")

        let received = try CLIRequest(url: try sent.url())

        XCTAssertEqual(received.text, text)
        XCTAssertTrue(received.summarize)
        XCTAssertEqual(received.translate, "ja")
        XCTAssertEqual(received.prompt, "- three bullets & no more")
    }

    func testURLRoundTripDefaults() throws {
        let received = try CLIRequest(url: try CLIRequest(text: "Hi", summarize: false, translate: nil, prompt: nil).url())

        XCTAssertEqual(received.text, "Hi")
        XCTAssertFalse(received.summarize)
        XCTAssertNil(received.translate)
        XCTAssertNil(received.prompt)
    }

    /// Regression: the app only rejected an empty text, so `text=%20` started a request that
    /// produced no audio and never finished.
    func testIncomingURLRejectsBlankText() {
        for raw in ["hibiki://speak?text=%20%0A", "hibiki://speak?text=", "hibiki://speak", "hibiki://speak?summarize=true"] {
            XCTAssertThrowsError(try CLIRequest(url: URL(string: raw)!), raw) { error in
                XCTAssertEqual(error as? CLIRequestError, .emptyText)
            }
        }
    }

    func testIncomingURLRejectsOtherSchemesAndHosts() {
        for raw in ["https://speak?text=hi", "hibiki://shout?text=hi"] {
            XCTAssertThrowsError(try CLIRequest(url: URL(string: raw)!), raw) { error in
                XCTAssertEqual(error as? CLIRequestError, .unsupportedURL)
            }
        }
    }

    func testIncomingURLRejectsOversizedRequests() throws {
        let huge = String(repeating: "a", count: CLIRequest.maxAcceptedURLBytes)
        let url = try XCTUnwrap(URL(string: "hibiki://speak?text=\(huge)"))

        XCTAssertThrowsError(try CLIRequest(url: url)) { error in
            guard case .urlTooLong = error as? CLIRequestError else {
                return XCTFail("expected urlTooLong, got \(error)")
            }
        }
    }

    func testIncomingURLAcceptsEverythingTheCLICanSend() throws {
        let text = String(repeating: "word ", count: 4_000)
        let url = try CLIRequest(text: text, summarize: false, translate: nil, prompt: nil).url()
        XCTAssertLessThanOrEqual(url.absoluteString.utf8.count, CLIRequest.maxCLIURLBytes)

        XCTAssertEqual(try CLIRequest(url: url).text, text)
    }

    func testBlankPromptInURLIsIgnored() throws {
        let received = try CLIRequest(url: URL(string: "hibiki://speak?text=hi&summarize=true&prompt=%20")!)
        XCTAssertNil(received.prompt)
    }
}
