import Foundation

/// Incrementally decodes a WAV stream and emits raw PCM payload bytes.
/// Hibiki's audio player expects PCM16 mono at 24kHz.
final class WAVStreamDecoder {
    private enum State {
        case awaitingHeader
        case streamingPCM
        case completed
    }

    enum DecodeError: LocalizedError {
        case invalidContainer
        case missingFormatChunk
        case invalidFormatChunk
        case unsupportedAudioFormat(Int)
        case unsupportedChannels(Int)
        case unsupportedSampleRate(Int)
        case unsupportedBitDepth(Int)
        case dataChunkNotFound
        case streamEndedBeforeHeaderComplete

        var errorDescription: String? {
            switch self {
            case .invalidContainer:
                return "Pocket TTS returned invalid WAV data."
            case .missingFormatChunk:
                return "Pocket TTS WAV stream is missing a format chunk."
            case .invalidFormatChunk:
                return "Pocket TTS WAV format chunk is malformed."
            case .unsupportedAudioFormat(let value):
                return "Pocket TTS WAV audio format \(value) is unsupported."
            case .unsupportedChannels(let value):
                return "Pocket TTS WAV channel count \(value) is unsupported."
            case .unsupportedSampleRate(let value):
                return "Pocket TTS WAV sample rate \(value) is unsupported."
            case .unsupportedBitDepth(let value):
                return "Pocket TTS WAV bit depth \(value) is unsupported."
            case .dataChunkNotFound:
                return "Pocket TTS WAV stream is missing a data chunk."
            case .streamEndedBeforeHeaderComplete:
                return "Pocket TTS WAV header ended unexpectedly."
            }
        }
    }

    private var state: State = .awaitingHeader
    private var buffer = Data()
    private var didValidateFormat = false
    private var dataBytesRemaining: Int?

    private let expectedSampleRate: Int
    private let expectedChannels: Int
    private let expectedBitsPerSample: Int

    init(expectedSampleRate: Int = 24_000, expectedChannels: Int = 1, expectedBitsPerSample: Int = 16) {
        self.expectedSampleRate = expectedSampleRate
        self.expectedChannels = expectedChannels
        self.expectedBitsPerSample = expectedBitsPerSample
    }

    func consume(_ data: Data) throws -> Data? {
        guard !data.isEmpty else { return nil }

        switch state {
        case .awaitingHeader:
            buffer.append(data)
            return try parseHeaderAndMaybeEmitPCM()
        case .streamingPCM:
            return consumePCM(data)
        case .completed:
            return nil
        }
    }

    func finalize() throws {
        switch state {
        case .awaitingHeader:
            if !buffer.isEmpty {
                throw DecodeError.streamEndedBeforeHeaderComplete
            }
        case .streamingPCM, .completed:
            return
        }
    }

    private func parseHeaderAndMaybeEmitPCM() throws -> Data? {
        guard buffer.count >= 12 else { return nil }

        guard fourCC(at: 0) == "RIFF", fourCC(at: 8) == "WAVE" else {
            throw DecodeError.invalidContainer
        }

        var cursor = 12
        while true {
            guard buffer.count >= cursor + 8 else { return nil }

            let chunkID = fourCC(at: cursor)
            let chunkSize = Int(readUInt32LE(at: cursor + 4))
            let chunkDataStart = cursor + 8
            let paddedChunkSize = chunkSize + (chunkSize % 2)

            if chunkID == "data" {
                guard didValidateFormat else {
                    throw DecodeError.missingFormatChunk
                }

                guard buffer.count >= chunkDataStart else { return nil }
                dataBytesRemaining = chunkSize
                state = .streamingPCM

                let availablePayloadCount = buffer.count - chunkDataStart
                let payloadCount = consumeCount(forAvailableCount: availablePayloadCount)
                guard payloadCount > 0 else {
                    buffer.removeSubrange(0..<chunkDataStart)
                    return nil
                }

                let payloadStart = chunkDataStart
                let payloadEnd = payloadStart + payloadCount
                let payload = Data(buffer[payloadStart..<payloadEnd])
                buffer.removeSubrange(0..<payloadEnd)
                return payload
            }

            guard buffer.count >= chunkDataStart + paddedChunkSize else { return nil }

            if chunkID == "fmt " {
                try validateFormatChunk(at: chunkDataStart, size: chunkSize)
                didValidateFormat = true
            }

            cursor = chunkDataStart + paddedChunkSize
        }
    }

    private func validateFormatChunk(at offset: Int, size: Int) throws {
        guard size >= 16 else {
            throw DecodeError.invalidFormatChunk
        }
        guard buffer.count >= offset + size else {
            throw DecodeError.invalidFormatChunk
        }

        let audioFormat = Int(readUInt16LE(at: offset))
        let channels = Int(readUInt16LE(at: offset + 2))
        let sampleRate = Int(readUInt32LE(at: offset + 4))
        let bitsPerSample = Int(readUInt16LE(at: offset + 14))

        guard audioFormat == 1 else {
            throw DecodeError.unsupportedAudioFormat(audioFormat)
        }
        guard channels == expectedChannels else {
            throw DecodeError.unsupportedChannels(channels)
        }
        guard sampleRate == expectedSampleRate else {
            throw DecodeError.unsupportedSampleRate(sampleRate)
        }
        guard bitsPerSample == expectedBitsPerSample else {
            throw DecodeError.unsupportedBitDepth(bitsPerSample)
        }
    }

    private func consumePCM(_ data: Data) -> Data? {
        let outputCount = consumeCount(forAvailableCount: data.count)
        guard outputCount > 0 else {
            state = .completed
            return nil
        }
        return outputCount == data.count ? data : Data(data.prefix(outputCount))
    }

    private func consumeCount(forAvailableCount availableCount: Int) -> Int {
        guard let remaining = dataBytesRemaining else {
            return availableCount
        }

        let count = min(availableCount, remaining)
        let updatedRemaining = remaining - count
        dataBytesRemaining = max(0, updatedRemaining)
        if updatedRemaining <= 0 {
            state = .completed
        }
        return count
    }

    private func fourCC(at offset: Int) -> String {
        guard buffer.count >= offset + 4 else { return "" }
        let slice = buffer[offset..<(offset + 4)]
        return String(data: slice, encoding: .ascii) ?? ""
    }

    private func readUInt16LE(at offset: Int) -> UInt16 {
        guard buffer.count >= offset + 2 else { return 0 }
        let b0 = UInt16(buffer[offset])
        let b1 = UInt16(buffer[offset + 1]) << 8
        return b0 | b1
    }

    private func readUInt32LE(at offset: Int) -> UInt32 {
        guard buffer.count >= offset + 4 else { return 0 }
        let b0 = UInt32(buffer[offset])
        let b1 = UInt32(buffer[offset + 1]) << 8
        let b2 = UInt32(buffer[offset + 2]) << 16
        let b3 = UInt32(buffer[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
