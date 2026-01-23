import AVFoundation

final class StreamingAudioPlayer {
    static let shared = StreamingAudioPlayer()

    // Expose engine for audio level monitoring
    private(set) var audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let formatConverterMixer = AVAudioMixerNode()  // Converts Int16 -> Float for time pitch
    private let timePitchNode = AVAudioUnitTimePitch()

    // Playback speed (1.0 = normal, up to 2.5x)
    var playbackSpeed: Float = 1.0 {
        didSet {
            timePitchNode.rate = playbackSpeed
        }
    }

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

    // Playback completion tracking
    private var scheduledBufferCount = 0
    private var completedBufferCount = 0
    private var isStreamFinished = false
    private var isStopping = false  // Flag to ignore callbacks during stop
    private var playbackGeneration = 0  // Incremented on each reset to invalidate old callbacks
    var onPlaybackComplete: (() -> Void)?

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
        // Only attach if not already attached
        if playerNode.engine == nil {
            audioEngine.attach(playerNode)
            audioEngine.attach(formatConverterMixer)
            audioEngine.attach(timePitchNode)

            // Connect player -> mixer (converts Int16 to Float) -> timePitch -> main mixer
            audioEngine.connect(
                playerNode,
                to: formatConverterMixer,
                format: pcmFormat
            )
            audioEngine.connect(
                formatConverterMixer,
                to: timePitchNode,
                format: nil  // Mixer outputs float format
            )
            audioEngine.connect(
                timePitchNode,
                to: audioEngine.mainMixerNode,
                format: nil
            )
        }

        // Apply current playback speed
        timePitchNode.rate = playbackSpeed

        audioEngine.prepare()
    }

    func enqueue(pcmData: Data) {
        print("[Hibiki] 🎵 AudioPlayer.enqueue: \(pcmData.count) bytes")
        bufferQueue.async { [weak self] in
            guard let self = self, !self.isStopping else { return }

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
                try audioEngine.start()
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
        let generation = playbackGeneration
        scheduledBufferCount += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            self?.bufferQueue.async {
                guard let self = self else { return }
                // Ignore callbacks from old playback sessions or during stopping
                guard !self.isStopping && self.playbackGeneration == generation else { return }
                self.completedBufferCount += 1
                self.checkPlaybackComplete()
            }
        }
    }

    /// Call this when the TTS stream has finished sending data
    func markStreamComplete() {
        bufferQueue.async { [weak self] in
            guard let self = self, !self.isStopping else { return }
            self.isStreamFinished = true
            self.checkPlaybackComplete()
        }
    }

    private func checkPlaybackComplete() {
        // Only fire completion when stream is done AND all buffers played
        guard !isStopping else { return }
        if isStreamFinished && completedBufferCount >= scheduledBufferCount && scheduledBufferCount > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onPlaybackComplete?()
            }
        }
    }

    func stop() {
        bufferQueue.sync { [weak self] in
            guard let self = self else { return }
            self.isStopping = true
            self.playbackGeneration += 1  // Invalidate all pending callbacks
            
            // Stop player node first (this cancels scheduled buffers)
            self.playerNode.stop()
            
            // Stop engine
            if self.isEngineRunning {
                self.audioEngine.stop()
                self.isEngineRunning = false
            }
            
            // Clear state
            self.pendingBuffers.removeAll()
            self.bufferedSampleCount = 0
            self.hasStartedPlayback = false
            self.scheduledBufferCount = 0
            self.completedBufferCount = 0
            self.isStreamFinished = false
            self.isStopping = false
        }
    }

    func reset() {
        stop()
        bufferQueue.sync { [weak self] in
            self?.setupAudioEngine()
        }
    }
}
