import XCTest
@testable import Hibiki

final class WAVStreamDecoderTests: XCTestCase {
    private func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    private func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    /// A PCM WAV file; `dataSize` overrides the size written in the data chunk header.
    private func wav(
        payload: Data,
        sampleRate: UInt32 = 24_000,
        channels: UInt16 = 1,
        bits: UInt16 = 16,
        dataSize: UInt32? = nil,
        extraChunk: Bool = false
    ) -> Data {
        var bytes: [UInt8] = []
        bytes += Array("RIFF".utf8) + le32(UInt32(36 + payload.count)) + Array("WAVE".utf8)
        bytes += Array("fmt ".utf8) + le32(16) + le16(1) + le16(channels) + le32(sampleRate)
        bytes += le32(sampleRate * UInt32(channels) * UInt32(bits) / 8) + le16(channels * bits / 8) + le16(bits)
        if extraChunk {
            // Odd-sized chunk: followed by one pad byte.
            bytes += Array("LIST".utf8) + le32(3) + [1, 2, 3, 0]
        }
        bytes += Array("data".utf8) + le32(dataSize ?? UInt32(payload.count))
        return Data(bytes) + payload
    }

    private func decode(_ data: Data, chunkSize: Int) throws -> Data {
        let decoder = WAVStreamDecoder()
        var output = Data()
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            if let pcm = try decoder.consume(Data(data[offset..<end])) {
                output.append(pcm)
            }
            offset = end
        }
        try decoder.finalize()
        return output
    }

    private let payload = Data((0..<1000).map { UInt8($0 % 251) })

    func testPayloadSurvivesAnyChunking() throws {
        let file = wav(payload: payload)
        for chunkSize in [1, 2, 7, 43, 44, 45, 512, file.count] {
            XCTAssertEqual(try decode(file, chunkSize: chunkSize), payload, "chunk size \(chunkSize)")
        }
    }

    func testChunksBeforeDataAreSkipped() throws {
        let file = wav(payload: payload, extraChunk: true)
        for chunkSize in [1, 5, file.count] {
            XCTAssertEqual(try decode(file, chunkSize: chunkSize), payload, "chunk size \(chunkSize)")
        }
    }

    func testBytesAfterDeclaredDataSizeAreIgnored() throws {
        let file = wav(payload: payload, dataSize: 600) + Data("LISTjunk".utf8)
        XCTAssertEqual(try decode(file, chunkSize: 64), payload.prefix(600))
    }

    /// Regression: a streaming server writes a placeholder data size. `0xFFFFFFFF` worked by
    /// accident, but `0` was taken literally and the whole response decoded to silence.
    func testPlaceholderDataSizeStreamsUntilTheEnd() throws {
        for placeholder: UInt32 in [0, .max] {
            let file = wav(payload: payload, dataSize: placeholder)
            for chunkSize in [1, 44, 300] {
                XCTAssertEqual(try decode(file, chunkSize: chunkSize), payload, "size \(placeholder), chunk \(chunkSize)")
            }
        }
    }

    func testUnsupportedFormatsAreRejected() {
        XCTAssertThrowsError(try decode(wav(payload: payload, sampleRate: 16_000), chunkSize: 64)) { error in
            guard case WAVStreamDecoder.DecodeError.unsupportedSampleRate(16_000) = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
        XCTAssertThrowsError(try decode(wav(payload: payload, channels: 2), chunkSize: 64))
        XCTAssertThrowsError(try decode(wav(payload: payload, bits: 8), chunkSize: 64))
    }

    func testNonWAVDataIsRejected() {
        XCTAssertThrowsError(try decode(Data("{\"detail\":\"error\"}".utf8), chunkSize: 64))
    }

    func testTruncatedHeaderIsAnError() {
        XCTAssertThrowsError(try decode(wav(payload: payload).prefix(20), chunkSize: 8))
    }
}
