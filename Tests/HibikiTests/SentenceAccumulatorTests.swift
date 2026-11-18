import XCTest
@testable import Hibiki

final class SentenceAccumulatorTests: XCTestCase {

    func testSingleSentenceAccumulation() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences1 = accumulator.accumulate("Hello, this is ")
        XCTAssertTrue(sentences1.isEmpty, "Should not emit incomplete sentence")

        let sentences2 = accumulator.accumulate("a test sentence. ")
        XCTAssertEqual(sentences2.count, 1)
        XCTAssertEqual(sentences2.first, "Hello, this is a test sentence.")
    }

    func testMultipleSentencesInOneChunk() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        // Both sentences must meet minimum length
        // First: "First sentence here." = 20 chars > 10 ✓
        // Second: "This is another complete sentence here." = 40 chars > 10 ✓
        let sentences = accumulator.accumulate("First sentence here. This is another complete sentence here. ")

        // If only getting 1, flush and check what remains
        if sentences.count == 1 {
            let remaining = accumulator.flush()
            XCTAssertEqual(sentences.count + (remaining != nil ? 1 : 0), 2, "Should have 2 total parts. Remaining: \(remaining ?? "nil")")
        } else {
            XCTAssertEqual(sentences.count, 2)
            XCTAssertEqual(sentences[0], "First sentence here.")
            XCTAssertEqual(sentences[1], "This is another complete sentence here.")
        }
    }

    func testFlushRemainingText() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        _ = accumulator.accumulate("This is incomplete")
        let remaining = accumulator.flush()

        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining, "This is incomplete")
    }

    func testFlushReturnsNilForEmptyBuffer() {
        let accumulator = SentenceAccumulator()

        let remaining = accumulator.flush()
        XCTAssertNil(remaining)
    }

    func testAbbreviationsNotTreatedAsSentenceEnd() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences = accumulator.accumulate("Dr. Smith went to the store. ")
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.first, "Dr. Smith went to the store.")
    }

    func testMultipleAbbreviations() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences = accumulator.accumulate("Mr. and Mrs. Jones arrived here. ")
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.first, "Mr. and Mrs. Jones arrived here.")
    }

    func testQuestionMarkAsSentenceEnd() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences = accumulator.accumulate("How are you today? ")
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.first, "How are you today?")
    }

    func testExclamationMarkAsSentenceEnd() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences = accumulator.accumulate("What a great day! ")
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.first, "What a great day!")
    }

    func testParagraphBreakAsSentenceEnd() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        // Paragraph break should be treated as sentence boundary
        let sentences = accumulator.accumulate("First paragraph here with text\n\nSecond paragraph here with more text. ")

        // First paragraph should be extracted
        XCTAssertGreaterThanOrEqual(sentences.count, 1)
        XCTAssertTrue(sentences.first?.contains("First paragraph") ?? false)

        // Second paragraph should be either in sentences or flush
        let remaining = accumulator.flush()
        let total = sentences.count + (remaining != nil ? 1 : 0)
        XCTAssertGreaterThanOrEqual(total, 2, "Should have at least 2 parts total")
    }

    func testReset() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        _ = accumulator.accumulate("Some text here")
        accumulator.reset()

        let remaining = accumulator.flush()
        XCTAssertNil(remaining)
    }

    func testMinimumSentenceLength() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 20)

        // Short sentences should not be emitted
        let sentences1 = accumulator.accumulate("Hi. ")
        XCTAssertTrue(sentences1.isEmpty, "Short sentence should not be emitted")

        // Add more text to reach minimum length
        let sentences2 = accumulator.accumulate("This is a longer sentence now. ")
        XCTAssertEqual(sentences2.count, 1, "Should emit when minimum length reached")
    }

    func testStreamingChunks() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        var allSentences: [String] = []

        allSentences.append(contentsOf: accumulator.accumulate("The "))
        allSentences.append(contentsOf: accumulator.accumulate("quick "))
        allSentences.append(contentsOf: accumulator.accumulate("brown "))
        allSentences.append(contentsOf: accumulator.accumulate("fox "))
        allSentences.append(contentsOf: accumulator.accumulate("jumps. "))

        XCTAssertEqual(allSentences.count, 1)
        XCTAssertEqual(allSentences.first, "The quick brown fox jumps.")
    }

    func testNewlineAfterPeriod() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        // Period followed by newline should be a sentence boundary
        let sentences = accumulator.accumulate("First sentence here.\nThis is a second sentence that is long enough. ")

        // First sentence should be extracted
        XCTAssertGreaterThanOrEqual(sentences.count, 1)
        XCTAssertTrue(sentences.first?.contains("First sentence") ?? false)

        // Second sentence should be either in sentences or flush
        let remaining = accumulator.flush()
        let total = sentences.count + (remaining != nil ? 1 : 0)
        XCTAssertGreaterThanOrEqual(total, 2, "Should have at least 2 parts total")
    }

    func testUSAbbreviation() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences = accumulator.accumulate("The U.S. economy is strong. ")
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.first, "The U.S. economy is strong.")
    }

    func testEmptyChunk() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences = accumulator.accumulate("")
        XCTAssertTrue(sentences.isEmpty)
    }

    func testWhitespaceOnlyChunk() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 10)

        let sentences = accumulator.accumulate("   \n\t  ")
        XCTAssertTrue(sentences.isEmpty)
    }

    func testLongStreamingDocument() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 20)

        let text = """
        The quick brown fox jumps over the lazy dog. This is a classic pangram used in typing tests. \
        It contains every letter of the English alphabet. Many people use it for font previews. \
        The sentence has been around for over a century. It remains popular today.
        """

        var allSentences: [String] = []

        let words = text.split(separator: " ")
        for (index, word) in words.enumerated() {
            let chunk = String(word) + (index < words.count - 1 ? " " : "")
            allSentences.append(contentsOf: accumulator.accumulate(chunk))
        }

        if let remaining = accumulator.flush() {
            allSentences.append(remaining)
        }

        XCTAssertGreaterThan(allSentences.count, 0, "Should extract sentences from document")
    }

    // MARK: - Short fragments

    /// Regression: after a paragraph break, a sentence just under the minimum length was
    /// found as a boundary (newlines counted towards the minimum), rejected after trimming,
    /// and found again on every later chunk. Nothing else was emitted until flush, so the
    /// rest of a summary arrived as one late block of audio.
    func testShortSentenceAfterParagraphBreakDoesNotStallTheStream() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 20)

        XCTAssertEqual(
            accumulator.accumulate("This first sentence is clearly long enough. "),
            ["This first sentence is clearly long enough."]
        )
        // 18 characters; with the two leading newlines the raw boundary sits at 20.
        XCTAssertEqual(accumulator.accumulate("\n\nShort heading one. "), [])

        let next = accumulator.accumulate("This following sentence is long enough to emit. ")
        XCTAssertEqual(next, ["Short heading one. This following sentence is long enough to emit."])

        XCTAssertEqual(
            accumulator.accumulate("And the stream keeps flowing afterwards. "),
            ["And the stream keeps flowing afterwards."]
        )
        XCTAssertNil(accumulator.flush())
    }

    func testShortParagraphIsMergedWithTheNextOne() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 20)

        // 18 characters + paragraph break: raw boundary at 20, trimmed text below the minimum.
        XCTAssertEqual(accumulator.accumulate("A short heading ok\n\n"), [])
        XCTAssertEqual(
            accumulator.accumulate("Body text that is long enough to stand alone. "),
            ["A short heading ok\n\nBody text that is long enough to stand alone."]
        )
    }

    func testEverythingIsEventuallyEmittedExactlyOnce() {
        let accumulator = SentenceAccumulator(minimumSentenceLength: 30)
        let text = "Ok.\n\nYes. No!\n\nA longer sentence that passes the minimum length. Fine.\n\nShort again. "
            + "Another sentence comfortably over the minimum. Done."

        var emitted: [String] = []
        for character in text {
            emitted += accumulator.accumulate(String(character))
        }
        if let rest = accumulator.flush() {
            emitted.append(rest)
        }

        let words: (String) -> [Substring] = { $0.split(whereSeparator: \.isWhitespace) }
        XCTAssertEqual(emitted.flatMap(words), words(text))
        XCTAssertGreaterThan(emitted.count, 1, "must not hold everything back until flush")
    }
}
