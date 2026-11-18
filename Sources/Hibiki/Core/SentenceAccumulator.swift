import Foundation

/// Accumulates streaming text chunks and emits complete sentences.
/// Used to bridge streaming LLM output to sentence-level pipeline stages.
final class SentenceAccumulator {
    private var buffer: String = ""
    private let minimumSentenceLength: Int

    /// Common abbreviations that shouldn't trigger sentence boundaries
    private static let abbreviations: Set<String> = [
        "Dr.", "Mr.", "Mrs.", "Ms.", "Prof.", "Sr.", "Jr.",
        "vs.", "etc.", "i.e.", "e.g.", "cf.", "al.",
        "Inc.", "Ltd.", "Corp.", "Co.",
        "Jan.", "Feb.", "Mar.", "Apr.", "Jun.", "Jul.", "Aug.", "Sep.", "Sept.", "Oct.", "Nov.", "Dec.",
        "Mon.", "Tue.", "Wed.", "Thu.", "Fri.", "Sat.", "Sun.",
        "St.", "Ave.", "Blvd.", "Rd.", "Apt.", "No.",
        "U.S.", "U.K.", "E.U."
    ]

    /// Initialize with optional minimum sentence length
    /// - Parameter minimumSentenceLength: Minimum characters before emitting (default: 20)
    init(minimumSentenceLength: Int = 20) {
        self.minimumSentenceLength = minimumSentenceLength
    }

    /// Accumulate a chunk of text and return any completed sentences
    /// - Parameter chunk: The text chunk to add
    /// - Returns: Array of complete sentences (may be empty)
    func accumulate(_ chunk: String) -> [String] {
        buffer += chunk
        return extractCompleteSentences()
    }

    /// Flush any remaining text in the buffer
    /// - Returns: The remaining text, or nil if empty
    func flush() -> String? {
        let remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remaining.isEmpty ? nil : remaining
    }

    /// Reset the accumulator state
    func reset() {
        buffer = ""
    }

    /// Extract complete sentences from the buffer, leaving incomplete text
    private func extractCompleteSentences() -> [String] {
        var sentences: [String] = []

        // findSentenceEnd only reports boundaries that leave a long-enough sentence, so a
        // short fragment is carried forward and emitted together with what follows it.
        while let sentenceEnd = findSentenceEnd() {
            let sentenceEndIndex = buffer.index(buffer.startIndex, offsetBy: sentenceEnd)
            sentences.append(
                String(buffer[..<sentenceEndIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            )

            // Remove extracted sentence from buffer
            buffer = String(buffer[sentenceEndIndex...])
                .trimmingCharacters(in: .init(charactersIn: " "))
        }

        return sentences
    }

    /// Find the end position of a complete sentence in the buffer
    /// - Returns: Character offset after the sentence terminator, or nil if no complete sentence
    private func findSentenceEnd() -> Int? {
        // Scan through buffer looking for sentence terminators
        var index = buffer.startIndex

        while index < buffer.endIndex {
            let char = buffer[index]

            // Check for sentence-ending punctuation
            if char == "." || char == "!" || char == "?" {
                // Check what follows the punctuation
                let nextIndex = buffer.index(after: index)

                // Must be followed by whitespace or newline to be a sentence end
                if nextIndex < buffer.endIndex {
                    let nextChar = buffer[nextIndex]
                    if nextChar.isWhitespace || nextChar.isNewline {
                        // For periods, check if this is an abbreviation
                        if char == "." && isAbbreviation(at: index) {
                            // Skip this period, it's an abbreviation
                            index = nextIndex
                            continue
                        }

                        // Found a valid sentence end
                        let position = buffer.distance(from: buffer.startIndex, to: nextIndex)

                        if isLongEnoughSentence(endingAt: nextIndex) {
                            return position
                        }
                    }
                }
            }

            // Check for paragraph break (double newline)
            if char == "\n" {
                let nextIndex = buffer.index(after: index)
                if nextIndex < buffer.endIndex && buffer[nextIndex] == "\n" {
                    let endIndex = buffer.index(after: nextIndex)
                    if isLongEnoughSentence(endingAt: endIndex) {
                        return buffer.distance(from: buffer.startIndex, to: endIndex)
                    }
                }
            }

            index = buffer.index(after: index)
        }

        return nil
    }

    /// The minimum applies to the text that would actually be emitted. Measuring the raw
    /// buffer instead let leading or trailing newlines push a short fragment over the limit;
    /// it was then rejected after trimming, and the same boundary was found again on every
    /// later chunk, so nothing more was emitted until the final flush.
    private func isLongEnoughSentence(endingAt endIndex: String.Index) -> Bool {
        buffer[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumSentenceLength
    }

    /// Check if the period at the given position is part of an abbreviation
    private func isAbbreviation(at periodIndex: String.Index) -> Bool {
        // Get the word ending at this period
        var wordStart = periodIndex
        while wordStart > buffer.startIndex {
            let prevIndex = buffer.index(before: wordStart)
            let char = buffer[prevIndex]
            if char.isWhitespace || (char.isPunctuation && char != ".") {
                break
            }
            wordStart = prevIndex
        }

        let endIndex = buffer.index(after: periodIndex)
        let word = String(buffer[wordStart..<endIndex])

        return Self.abbreviations.contains(word)
    }
}
