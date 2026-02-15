import Foundation

/// Splits text into chunks suitable for TTS processing
enum TextChunker {
    /// Default maximum chunk size (characters)
    /// OpenAI TTS limit is 4096, we use 2500 for safety margin
    static let defaultMaxLength = 2500

    /// Minimum chunk size to avoid tiny fragments
    private static let minimumChunkSize = 100

    /// Split text into chunks, respecting natural boundaries
    /// - Parameters:
    ///   - text: The input text to split
    ///   - maxLength: Maximum characters per chunk (default: 2500)
    /// - Returns: Array of text chunks, each under maxLength
    static func chunk(_ text: String, maxLength: Int = defaultMaxLength) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If text fits in one chunk, return as-is
        guard trimmed.count > maxLength else {
            return trimmed.isEmpty ? [] : [trimmed]
        }

        var chunks: [String] = []
        var remaining = trimmed

        while !remaining.isEmpty {
            if remaining.count <= maxLength {
                let finalChunk = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalChunk.isEmpty {
                    chunks.append(finalChunk)
                }
                break
            }

            // Find best split point within maxLength
            let searchRange = String(remaining.prefix(maxLength))

            // Try sentence boundaries first (. ! ? followed by space/newline, or paragraph break)
            if let splitIndex = findSentenceBoundary(in: searchRange) {
                let chunk = String(remaining.prefix(splitIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                remaining = String(remaining.dropFirst(splitIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            // Try clause boundaries (, ; :)
            if let splitIndex = findClauseBoundary(in: searchRange) {
                let chunk = String(remaining.prefix(splitIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                remaining = String(remaining.dropFirst(splitIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            // Fall back to word boundary
            if let splitIndex = findWordBoundary(in: searchRange) {
                let chunk = String(remaining.prefix(splitIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                remaining = String(remaining.dropFirst(splitIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            // Last resort: hard cut at maxLength
            let chunk = String(remaining.prefix(maxLength))
            chunks.append(chunk)
            remaining = String(remaining.dropFirst(maxLength))
        }

        return chunks.filter { !$0.isEmpty }
    }

    /// Find the last sentence boundary in the text
    /// Returns the index after the terminator (where to split)
    private static func findSentenceBoundary(in text: String) -> Int? {
        // Sentence terminators followed by whitespace
        let terminators = [". ", ".\n", ".\t", "! ", "!\n", "? ", "?\n", "\n\n"]

        var bestIndex: Int? = nil

        for terminator in terminators {
            if let range = text.range(of: terminator, options: .backwards) {
                let index = text.distance(from: text.startIndex, to: range.upperBound)
                if bestIndex == nil || index > bestIndex! {
                    bestIndex = index
                }
            }
        }

        // Also check for sentence end at the very end of text
        let endTerminators = [".", "!", "?"]
        for terminator in endTerminators {
            if text.hasSuffix(terminator) {
                let index = text.count
                if bestIndex == nil || index > bestIndex! {
                    bestIndex = index
                }
            }
        }

        // Require minimum chunk size to avoid tiny fragments
        if let idx = bestIndex, idx >= minimumChunkSize {
            return idx
        }
        return nil
    }

    /// Find the last clause boundary in the text
    private static func findClauseBoundary(in text: String) -> Int? {
        let separators = [", ", "; ", ": "]
        var bestIndex: Int? = nil

        for separator in separators {
            if let range = text.range(of: separator, options: .backwards) {
                let index = text.distance(from: text.startIndex, to: range.upperBound)
                if bestIndex == nil || index > bestIndex! {
                    bestIndex = index
                }
            }
        }

        if let idx = bestIndex, idx >= minimumChunkSize {
            return idx
        }
        return nil
    }

    /// Find the last word boundary (space) in the text
    private static func findWordBoundary(in text: String) -> Int? {
        if let range = text.range(of: " ", options: .backwards) {
            let index = text.distance(from: text.startIndex, to: range.upperBound)
            // Lower threshold for word boundaries since it's our last natural option
            if index >= 50 {
                return index
            }
        }
        return nil
    }
}
