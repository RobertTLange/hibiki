import ArgumentParser
import AppKit
import Foundation
import HibikiCLICore

/// CLI tool for Hibiki TTS
/// Opens a URL scheme to communicate with the running Hibiki app
@main
struct HibikiCLI: ParsableCommand {
    private static let hibikiBundleIdentifier = "com.superlisten.hibiki"
    private static let applicationsBundlePath = "/Applications/Hibiki.app"

    static let configuration = CommandConfiguration(
        commandName: "hibiki",
        abstract: "Command-line interface for Hibiki TTS",
        discussion: """
            Sends text to the Hibiki app for text-to-speech processing.
            The Hibiki app must be running or will be launched automatically.

            Examples:
              hibiki --text "Hello world"
              hibiki --file-name README.md
              hibiki --text "Long article..." --summarize
              hibiki --file-name Sources/HibikiCLI/HibikiCLI.swift --summarize
              hibiki --text "Hello" --translate ja
              hibiki --text "Article..." --summarize --translate fr
              hibiki --text "Article..." --summarize --prompt "Summarize in 3 bullet points."
            """
    )

    @Option(name: .long, help: "Text to process")
    var text: String?

    @Option(name: .long, help: "Path to text/markdown/code file to process")
    var fileName: String?

    @Flag(name: .long, help: "Summarize the text before speaking")
    var summarize: Bool = false

    @Option(name: .long, help: "Custom summarization prompt (requires --summarize)")
    var prompt: String?

    @Option(name: .long, help: "Target language for translation (en, fr, de, ja, es)")
    var translate: String?

    mutating func validate() throws {
        do {
            let request = try buildRequest()
            try request.validate()
        } catch let error as CLIInputError {
            throw ValidationError(error.userMessage)
        } catch let error as CLIRequestError {
            throw ValidationError(error.userMessage)
        }
    }

    func run() throws {
        let request: CLIRequest
        do {
            request = try buildRequest()
        } catch let error as CLIInputError {
            fputs("Error: \(error.userMessage)\n", stderr)
            throw ExitCode.failure
        } catch let error as CLIRequestError {
            fputs("Error: \(error.userMessage)\n", stderr)
            throw ExitCode.failure
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        if DoNotDisturbPolicy.isEnabled() {
            print(DoNotDisturbPolicy.cliSuppressedNotice)
            return
        }

        let baseURL: URL
        do {
            baseURL = try request.url()
        } catch let error as CLIRequestError {
            fputs("Error: \(error.userMessage)\n", stderr)
            throw ExitCode.failure
        }

        var requestURL = baseURL
        if let activeDisplayID = activeDisplayIDForInvocation(),
           var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "display", value: String(activeDisplayID)))
            components.queryItems = items
            if let enrichedURL = components.url {
                requestURL = enrichedURL
            }
        }

        // Check URL length (practical limit ~32KB)
        if let urlString = requestURL.absoluteString.data(using: .utf8), urlString.count > 32000 {
            fputs("Error: Input too long for URL transport (~32KB after encoding). Try --summarize or split the file.\n", stderr)
            throw ExitCode(2)
        }

        if let errorMessage = dispatchToHibikiApp(requestURL) {
            fputs("Error: Failed to open Hibiki app - \(errorMessage)\n", stderr)
            throw ExitCode(3)
        }

        // Success - the app will handle the request
        print("Request sent to Hibiki")
    }

    private func buildRequest() throws -> CLIRequest {
        let resolvedText = try CLIInputResolver.resolve(text: text, fileName: fileName)
        return CLIRequest(text: resolvedText, summarize: summarize, translate: translate, prompt: prompt)
    }

    private func dispatchToHibikiApp(_ requestURL: URL) -> String? {
        let request = requestURL.absoluteString
        var attempts: [[String]] = []

        if let runningBundleURL = runningHibikiBundleURL() {
            attempts.append(["-g", "-a", runningBundleURL.path, request])
        }

        if let installedBundleURL = installedHibikiBundleURL() {
            attempts.append(["-g", "-a", installedBundleURL.path, request])
        }

        attempts.append(["-g", "-b", Self.hibikiBundleIdentifier, request])

        var seen = Set<String>()
        for arguments in attempts {
            let key = arguments.joined(separator: "\u{1f}")
            if !seen.insert(key).inserted {
                continue
            }

            if runOpen(arguments: arguments) != nil {
                continue
            }
            return nil
        }

        let joinedAttempts = attempts
            .map { "/usr/bin/open \($0.joined(separator: " "))" }
            .joined(separator: " | ")
        return "all launch attempts failed: \(joinedAttempts)"
    }

    private func runningHibikiBundleURL() -> URL? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: Self.hibikiBundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID })?
            .bundleURL
    }

    private func installedHibikiBundleURL() -> URL? {
        let bundleURL = URL(fileURLWithPath: Self.applicationsBundlePath)
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            return nil
        }
        guard let bundle = Bundle(url: bundleURL),
              bundle.bundleIdentifier == Self.hibikiBundleIdentifier else {
            return nil
        }
        return bundleURL
    }

    private func runOpen(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }

        process.waitUntilExit()

        guard process.terminationStatus != 0 else {
            return nil
        }

        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if let stderr = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !stderr.isEmpty {
            return stderr
        }
        return "open exited with status \(process.terminationStatus)"
    }

    private func activeDisplayIDForInvocation() -> UInt32? {
        guard let windowInfos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else {
            return nil
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if let displayID = firstDisplayID(in: windowInfos, matchingPID: frontmostPID) {
            return displayID
        }

        if let displayID = firstDisplayID(in: windowInfos, matchingPID: nil) {
            return displayID
        }

        return displayIDAtGlobalPoint(NSEvent.mouseLocation)
    }

    private func firstDisplayID(in windowInfos: [[String: Any]], matchingPID: pid_t?) -> UInt32? {
        for info in windowInfos {
            if let matchingPID,
               let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
               ownerPID != matchingPID {
                continue
            }

            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }

            if let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool, !isOnscreen {
                continue
            }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 1,
                  bounds.height > 1 else {
                continue
            }

            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if let displayID = displayIDAtGlobalPoint(center) {
                return displayID
            }
        }

        return nil
    }

    private func displayIDAtGlobalPoint(_ point: CGPoint) -> UInt32? {
        var displayID = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        let result = withUnsafeMutablePointer(to: &displayID) { displayPtr in
            CGGetDisplaysWithPoint(point, 1, displayPtr, &displayCount)
        }

        guard result == .success, displayCount > 0 else {
            return nil
        }
        return displayID
    }
}
