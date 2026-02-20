import Foundation

public enum CLIInputError: Error, Equatable {
    case missingInput
    case conflictingInputs
    case emptyText
    case invalidFileName
    case fileNotFound(String)
    case fileIsDirectory(String)
    case fileReadFailed(String)
    case nonUTF8File(String)
    case emptyFileContent(String)
}

public struct CLIInputResolver {
    public static func resolve(text: String?, fileName: String?) throws -> String {
        let hasText = text != nil
        let hasFileName = fileName != nil

        switch (hasText, hasFileName) {
        case (false, false):
            throw CLIInputError.missingInput
        case (true, true):
            throw CLIInputError.conflictingInputs
        case (true, false):
            let rawText = text ?? ""
            if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CLIInputError.emptyText
            }
            return rawText
        case (false, true):
            let resolved = try resolveFromFile(fileName ?? "")
            if resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CLIInputError.emptyFileContent(fileName ?? "")
            }
            return resolved
        }
    }

    private static func resolveFromFile(_ fileName: String) throws -> String {
        let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            throw CLIInputError.invalidFileName
        }

        let expandedName = NSString(string: trimmedName).expandingTildeInPath
        let inputURL: URL
        if expandedName.hasPrefix("/") {
            inputURL = URL(fileURLWithPath: expandedName).standardizedFileURL
        } else {
            let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            inputURL = currentDirectoryURL.appendingPathComponent(expandedName).standardizedFileURL
        }

        var isDirectory: ObjCBool = false
        let path = inputURL.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw CLIInputError.fileNotFound(trimmedName)
        }
        if isDirectory.boolValue {
            throw CLIInputError.fileIsDirectory(trimmedName)
        }

        let data: Data
        do {
            data = try Data(contentsOf: inputURL)
        } catch {
            throw CLIInputError.fileReadFailed(trimmedName)
        }

        guard var decoded = String(data: data, encoding: .utf8) else {
            throw CLIInputError.nonUTF8File(trimmedName)
        }

        decoded = normalizeLineEndings(decoded)
        decoded = removeByteOrderMark(decoded)

        if isMarkdownFile(path: trimmedName) {
            return MarkdownCleaner.cleanBalanced(decoded)
        }

        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMarkdownFile(path: String) -> Bool {
        let lowercasedExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return lowercasedExtension == "md" || lowercasedExtension == "markdown"
    }

    static func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func removeByteOrderMark(_ text: String) -> String {
        if text.hasPrefix("\u{FEFF}") {
            return String(text.dropFirst())
        }
        return text
    }
}

public struct MarkdownCleaner {
    public static func cleanBalanced(_ markdown: String) -> String {
        var cleaned = markdown
        cleaned = stripTopFrontMatter(from: cleaned)
        cleaned = stripHTMLComments(from: cleaned)

        let lines = CLIInputResolver.normalizeLineEndings(cleaned).split(separator: "\n", omittingEmptySubsequences: false)
        var output: [String] = []
        var inCodeFence = false

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeFence {
                    output.append("End code.")
                } else {
                    output.append("Code:")
                }
                inCodeFence.toggle()
                continue
            }

            if inCodeFence {
                output.append(line)
                continue
            }

            if let heading = extractHeading(from: line) {
                output.append(heading)
                continue
            }

            if let listItem = extractListItem(from: line) {
                output.append(cleanInlineMarkdown(listItem, preserveStandaloneURL: false))
                continue
            }

            let preserveURL = isStandaloneURL(trimmed)
            output.append(cleanInlineMarkdown(line, preserveStandaloneURL: preserveURL))
        }

        return collapseExcessBlankLines(in: output.joined(separator: "\n"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTopFrontMatter(from text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return text }
        guard lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return text }

        for index in 1..<lines.count {
            let marker = lines[index].trimmingCharacters(in: .whitespaces)
            if marker == "---" || marker == "..." {
                if index + 1 >= lines.count {
                    return ""
                }
                return lines[(index + 1)...].joined(separator: "\n")
            }
        }

        return text
    }

    private static func stripHTMLComments(from text: String) -> String {
        let pattern = "<!--[\\s\\S]*?-->"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private static func extractHeading(from line: String) -> String? {
        let pattern = "^\\s*(#{1,6})\\s+(.+?)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let levelRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let level = line[levelRange].count
        let headingText = cleanInlineMarkdown(String(line[textRange]), preserveStandaloneURL: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headingText.isEmpty else { return nil }

        if level == 1 {
            return headingText.hasSuffix(".") ? headingText : "\(headingText)."
        }
        return "Section: \(headingText)"
    }

    private static func extractListItem(from line: String) -> String? {
        let patterns = [
            "^\\s*[-*+]\\s+\\[[ xX]\\]\\s+(.+?)\\s*$",
            "^\\s*[-*+]\\s+(.+?)\\s*$",
            "^\\s*\\d+[\\.)]\\s+(.+?)\\s*$"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  let itemRange = Range(match.range(at: 1), in: line) else {
                continue
            }
            let item = String(line[itemRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty {
                return item
            }
        }

        return nil
    }

    private static func cleanInlineMarkdown(_ line: String, preserveStandaloneURL: Bool) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if preserveStandaloneURL, isStandaloneURL(trimmed) {
            return trimmed
        }

        var cleaned = line
        cleaned = replaceMarkdownLinks(in: cleaned)
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "__", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "_", with: "")
        cleaned = cleaned.replacingOccurrences(of: "~~", with: "")
        cleaned = cleaned.replacingOccurrences(of: ">", with: "")
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    private static func replaceMarkdownLinks(in text: String) -> String {
        let pattern = "\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }

    private static func isStandaloneURL(_ text: String) -> Bool {
        let pattern = "^https?://\\S+$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func collapseExcessBlankLines(in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var output: [String] = []
        var consecutiveBlanks = 0

        for rawLine in lines {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                consecutiveBlanks += 1
                if consecutiveBlanks <= 2 {
                    output.append("")
                }
            } else {
                consecutiveBlanks = 0
                output.append(line.trimmingCharacters(in: .whitespaces))
            }
        }

        return output.joined(separator: "\n")
    }
}

public extension CLIInputError {
    var userMessage: String {
        switch self {
        case .missingInput:
            return "Provide exactly one input source: --text or --file-name"
        case .conflictingInputs:
            return "Use only one input source at a time: --text or --file-name"
        case .emptyText:
            return "Text cannot be empty"
        case .invalidFileName:
            return "File name cannot be empty"
        case .fileNotFound(let fileName):
            return "File not found: \(fileName)"
        case .fileIsDirectory(let fileName):
            return "Expected a file but received a directory: \(fileName)"
        case .fileReadFailed(let fileName):
            return "Failed to read file: \(fileName)"
        case .nonUTF8File(let fileName):
            return "Unsupported file encoding for \(fileName). Expected UTF-8 text."
        case .emptyFileContent(let fileName):
            return "File content is empty after cleanup: \(fileName)"
        }
    }
}
