import AVFoundation

final class StreamingAudioPlayer {
    static let shared = StreamingAudioPlayer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    // PCM format matching OpenAI TTS output: 24kHz, 16-bit signed int, mono
    private let pcmFormat: AVAudioFormat

    // Buffer queue for smooth playback
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private let bufferQueue = DispatchQueue(label: "audio.buffer.queue")

    // Minimum buffer before starting playback (latency tradeoff)
    private let minimumBufferSize = 4800 // 0.2 seconds at 24kHz
    private var bufferedSampleCount = 0
    private var hasStartedPlayback = false
    private var isEngineRunning = false

    private init() {
        pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        )!

        setupAudioEngine()
    }

    private func setupAudioEngine() {
        engine.attach(playerNode)

        // Connect player to main mixer
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: pcmFormat
        )

        engine.prepare()
    }

    func enqueue(pcmData: Data) {
        print("[Hibiki] 🎵 AudioPlayer.enqueue: \(pcmData.count) bytes")
        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            // Convert raw bytes to AVAudioPCMBuffer
            guard let buffer = self.createBuffer(from: pcmData) else {
                print("[Hibiki] ❌ Failed to create audio buffer")
                return
            }

            self.pendingBuffers.append(buffer)
            self.bufferedSampleCount += Int(buffer.frameLength)
            print("[Hibiki] 🎵 Buffered samples: \(self.bufferedSampleCount)/\(self.minimumBufferSize)")

            // Start playback once we have enough buffered
            if !self.hasStartedPlayback &&
               self.bufferedSampleCount >= self.minimumBufferSize {
                print("[Hibiki] 🎵 Starting playback...")
                self.startPlayback()
            } else if self.hasStartedPlayback {
                // Schedule buffer immediately if already playing
                self.scheduleBuffer(buffer)
            }
        }
    }

    private func createBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count / 2) // 16-bit = 2 bytes per sample

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: frameCount
        ) else { return nil }

        buffer.frameLength = frameCount

        // Copy data into buffer
        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, data.count)
            }
        }

        return buffer
    }

    private func startPlayback() {
        do {
            if !isEngineRunning {
                print("[Hibiki] 🎵 Starting audio engine...")
                try engine.start()
                isEngineRunning = true
                print("[Hibiki] ✅ Audio engine started")
            }

            // Schedule all pending buffers
            print("[Hibiki] 🎵 Scheduling \(pendingBuffers.count) pending buffers")
            for buffer in pendingBuffers {
                scheduleBuffer(buffer)
            }
            pendingBuffers.removeAll()

            playerNode.play()
            hasStartedPlayback = true
            print("[Hibiki] ✅ Audio playback started")
        } catch {
            print("[Hibiki] ❌ Failed to start audio engine: \(error)")
        }
    }

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.playerNode.stop()
            if self.isEngineRunning {
                self.engine.stop()
                self.isEngineRunning = false
            }
            self.pendingBuffers.removeAll()
            self.bufferedSampleCount = 0
            self.hasStartedPlayback = false
        }
    }

    func reset() {
        stop()
        bufferQueue.async { [weak self] in
            self?.setupAudioEngine()
        }
    }
}
