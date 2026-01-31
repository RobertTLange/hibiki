import ArgumentParser
import AppKit
import Foundation
import HibikiCLICore

/// CLI tool for Hibiki TTS
/// Opens a URL scheme to communicate with the running Hibiki app
@main
struct HibikiCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hibiki",
        abstract: "Command-line interface for Hibiki TTS",
        discussion: """
            Sends text to the Hibiki app for text-to-speech processing.
            The Hibiki app must be running or will be launched automatically.

            Examples:
              hibiki --text "Hello world"
              hibiki --text "Long article..." --summarize
              hibiki --text "Hello" --translate ja
              hibiki --text "Article..." --summarize --translate fr
              hibiki --text "Article..." --summarize --prompt "Summarize in 3 bullet points."
            """
    )

    @Option(name: .long, help: "Text to process")
    var text: String

    @Flag(name: .long, help: "Summarize the text before speaking")
    var summarize: Bool = false

    @Option(name: .long, help: "Custom summarization prompt (requires --summarize)")
    var prompt: String?

    @Option(name: .long, help: "Target language for translation (en, fr, de, ja, es)")
    var translate: String?

    mutating func validate() throws {
        let request = CLIRequest(text: text, summarize: summarize, translate: translate, prompt: prompt)
        do {
            try request.validate()
        } catch let error as CLIRequestError {
            throw ValidationError(error.userMessage)
        }
    }

    func run() throws {
        let request = CLIRequest(text: text, summarize: summarize, translate: translate, prompt: prompt)
        let url: URL
        do {
            url = try request.url()
        } catch let error as CLIRequestError {
            fputs("Error: \(error.userMessage)\n", stderr)
            throw ExitCode.failure
        }

        // Check URL length (practical limit ~32KB)
        if let urlString = url.absoluteString.data(using: .utf8), urlString.count > 32000 {
            fputs("Error: Text too long (exceeds 32KB after URL encoding)\n", stderr)
            throw ExitCode(2)
        }

        // Open the URL to send to the Hibiki app
        let workspace = NSWorkspace.shared

        // Use completion handler to know if it succeeded
        let semaphore = DispatchSemaphore(value: 0)
        var openError: Error?

        workspace.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            openError = error
            semaphore.signal()
        }

        // Wait for the open operation to complete
        semaphore.wait()

        if let error = openError {
            fputs("Error: Failed to open Hibiki app - \(error.localizedDescription)\n", stderr)
            throw ExitCode(3)
        }

        // Success - the app will handle the request
        print("Request sent to Hibiki")
    }
}
