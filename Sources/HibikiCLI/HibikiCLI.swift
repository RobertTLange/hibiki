import ArgumentParser
import AppKit
import Foundation

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
            """
    )

    @Option(name: .long, help: "Text to process")
    var text: String

    @Flag(name: .long, help: "Summarize the text before speaking")
    var summarize: Bool = false

    @Option(name: .long, help: "Target language for translation (en, fr, de, ja, es)")
    var translate: String?

    mutating func validate() throws {
        // Validate text is not empty
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("Text cannot be empty")
        }

        // Validate language code if provided
        if let lang = translate {
            let validLanguages = ["en", "fr", "de", "ja", "es"]
            guard validLanguages.contains(lang.lowercased()) else {
                throw ValidationError("Invalid language code '\(lang)'. Use: en, fr, de, ja, es")
            }
        }
    }

    func run() throws {
        // Build URL components
        var components = URLComponents()
        components.scheme = "hibiki"
        components.host = "speak"

        var queryItems: [URLQueryItem] = []

        // Add text parameter
        queryItems.append(URLQueryItem(name: "text", value: text))

        // Add summarize flag if set
        if summarize {
            queryItems.append(URLQueryItem(name: "summarize", value: "true"))
        }

        // Add translate parameter if set
        if let lang = translate {
            queryItems.append(URLQueryItem(name: "translate", value: lang.lowercased()))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
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
