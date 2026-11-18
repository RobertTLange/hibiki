import XCTest
@testable import Hibiki

final class HistoryDecodingTests: XCTestCase {
    private func encode(_ entries: [HistoryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entries)
    }

    private func entry(_ text: String) -> HistoryEntry {
        HistoryEntry(text: text, voice: "coral", inputTokens: 10, audioFileName: "\(text).pcm", ttsCost: 0.01)
    }

    func testRoundTrip() throws {
        let decoded = try HistoryManager.decodeEntries(from: try encode([entry("a"), entry("b")]))
        XCTAssertEqual(decoded.entries.map(\.text), ["a", "b"])
        XCTAssertEqual(decoded.droppedCount, 0)
    }

    /// Regression: one entry that failed to decode threw away the entire history, and the
    /// next save then overwrote the file with an empty list.
    func testOneDamagedEntryDoesNotDiscardTheRest() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encode([entry("a"), entry("b"), entry("c")])) as? [[String: Any]]
        )
        json[1].removeValue(forKey: "audioFileName")
        json[1]["timestamp"] = 42

        let decoded = try HistoryManager.decodeEntries(from: try JSONSerialization.data(withJSONObject: json))

        XCTAssertEqual(decoded.entries.map(\.text), ["a", "c"])
        XCTAssertEqual(decoded.droppedCount, 1)
    }

    func testOptionalFieldsMayBeAbsent() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try encode([entry("a")])) as? [[String: Any]]
        )
        for key in ["summarizedText", "llmCost", "translatedText", "translationCost", "targetLanguage"] {
            json[0].removeValue(forKey: key)
        }

        let decoded = try HistoryManager.decodeEntries(from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.droppedCount, 0)
    }

    func testNonArrayFileIsAnError() {
        XCTAssertThrowsError(try HistoryManager.decodeEntries(from: Data("{\"oops\":true}".utf8)))
        XCTAssertThrowsError(try HistoryManager.decodeEntries(from: Data("[{\"id\":".utf8)))
    }
}
