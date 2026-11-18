import XCTest
@testable import Hibiki

final class TextChunkerTests: XCTestCase {
    private func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace)
    }

    func testShortTextIsOneTrimmedChunk() {
        XCTAssertEqual(TextChunker.chunk("  Hello there.\n"), ["Hello there."])
    }

    func testBlankTextYieldsNoChunks() {
        XCTAssertEqual(TextChunker.chunk(""), [])
        XCTAssertEqual(TextChunker.chunk(" \n\t "), [])
    }

    func testLongProseKeepsEveryWordAndRespectsTheLimit() {
        let sentence = "The quick brown fox jumps over the lazy dog, twice, before lunch. "
        let text = String(repeating: sentence, count: 120)  // ~7900 chars

        let chunks = TextChunker.chunk(text)

        XCTAssertGreaterThan(chunks.count, 2)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= TextChunker.defaultMaxLength })
        XCTAssertEqual(chunks.flatMap(words), words(text))
        // Prose is cut at sentence ends, not mid-sentence.
        XCTAssertTrue(chunks.allSatisfy { $0.hasSuffix(".") })
    }

    func testTextWithoutSentenceEndsFallsBackToClausesThenWords() {
        let clauses = String(repeating: "alpha beta gamma, ", count: 60)
        let clauseChunks = TextChunker.chunk(clauses, maxLength: 200)
        XCTAssertTrue(clauseChunks.allSatisfy { $0.count <= 200 && $0.hasSuffix(",") })
        XCTAssertEqual(clauseChunks.flatMap(words), words(clauses))

        let plain = String(repeating: "word ", count: 300)
        let wordChunks = TextChunker.chunk(plain, maxLength: 200)
        XCTAssertTrue(wordChunks.allSatisfy { $0.count <= 200 })
        XCTAssertEqual(wordChunks.flatMap(words), words(plain))
    }

    func testUnbrokenTextIsHardCutWithoutLosingCharacters() {
        let blob = String(repeating: "x", count: 1050)
        let chunks = TextChunker.chunk(blob, maxLength: 200)

        XCTAssertEqual(chunks.map(\.count), [200, 200, 200, 200, 200, 50])
        XCTAssertEqual(chunks.joined(), blob)
    }

    func testNonLatinTextIsChunkedByCharacterCount() {
        let text = String(repeating: "これは日本語の文章です。", count: 100)  // no ASCII spaces
        let chunks = TextChunker.chunk(text, maxLength: 300)

        XCTAssertTrue(chunks.allSatisfy { $0.count <= 300 })
        XCTAssertEqual(chunks.joined(), text)
    }
}
