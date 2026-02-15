import AVFoundation

final class StreamingAudioPlayer {
    static let shared = StreamingAudioPlayer()

    // Expose engine for audio level monitoring
    private(set) var audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let formatConverterMixer = AVAudioMixerNode()  // Converts Int16 -> Float for time pitch
    private let timePitchNode = AVAudioUnitTimePitch()
    private let gainNode = AVAudioUnitEQ(numberOfBands: 0)
    private let maxPlaybackVolume: Float = 3.0
    private var isPaused = false

    // Playback speed (1.0 = normal, up to 2.5x)
    var playbackSpeed: Float = 1.0 {
        didSet {
            // Track accumulated progress before speed change
            if hasStartedPlayback, let startTime = playbackStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                accumulatedVirtualTime += elapsed * Double(oldValue)
                playbackStartTime = Date()  // Reset start time for new speed segment
            }
            timePitchNode.rate = playbackSpeed
            timePitchNode.bypass = playbackSpeed == 1.0
        }
    }

    // Playback volume (0.0 = muted, 1.0 = full volume)
    private var playbackVolumeValue: Float = 1.0
    var playbackVolume: Float {
        get { playbackVolumeValue }
        set {
            applyVolume(newValue)
        }
    }

    // PCM format matching OpenAI TTS output: 24kHz, 16-bit signed int, mono
    private let pcmFormat: AVAudioFormat
    private let floatFormat: AVAudioFormat

    // Buffer queue for smooth playback
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private let bufferQueue = DispatchQueue(label: "audio.buffer.queue")
    private var pendingPCMBytes = Data()

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

    // Playback position tracking for text highlighting
    private var totalScheduledSamples: Int64 = 0
    private var playbackStartTime: Date?
    private var estimatedTotalDuration: TimeInterval = 0
    private var accumulatedVirtualTime: TimeInterval = 0  // Tracks progress across speed changes

    /// Set the estimated duration based on text length (called before playback starts)
    /// Uses ~15.5 chars/second as typical TTS speaking rate at 1x speed
    func setEstimatedDuration(forTextLength charCount: Int) {
        estimatedTotalDuration = Double(charCount) / 15.5
    }

    /// Current playback progress as a value from 0.0 to 1.0
    /// Uses time-based estimation while streaming, then switches to sample-accurate progress once complete
    var currentPlaybackProgress: Double {
        guard hasStartedPlayback, !isStopping else {
            return 0.0
        }

        // Once the stream is complete, prefer sample-accurate progress based on the audio length.
        if isStreamFinished,
           !isPaused,
           totalScheduledSamples > 0,
           let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
            let playedSamples = Double(playerTime.sampleTime)
            let progress = playedSamples / Double(totalScheduledSamples)
            return min(1.0, max(0.0, progress))
        }

        guard estimatedTotalDuration > 0 else {
            return 0.0
        }

        var totalVirtualTime = accumulatedVirtualTime
        if let startTime = playbackStartTime, !isPaused {
            let elapsed = Date().timeIntervalSince(startTime)
            // Account for playback speed and accumulated time from previous speed segments
            let currentSegmentVirtualTime = elapsed * Double(playbackSpeed)
            totalVirtualTime += currentSegmentVirtualTime
        }
        let progress = totalVirtualTime / estimatedTotalDuration
        return min(1.0, max(0.0, progress))
    }

    private init() {
        pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        )!
        floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!

        setupAudioEngine()
    }

    private func setupAudioEngine() {
        // Only attach if not already attached
        if playerNode.engine == nil {
            audioEngine.attach(playerNode)
            audioEngine.attach(formatConverterMixer)
            audioEngine.attach(gainNode)
            audioEngine.attach(timePitchNode)

            // Connect player -> mixer (converts Int16 to Float) -> gain -> timePitch -> main mixer
            audioEngine.connect(
                playerNode,
                to: formatConverterMixer,
                format: pcmFormat
            )
            audioEngine.connect(
                formatConverterMixer,
                to: gainNode,
                format: floatFormat
            )
            audioEngine.connect(
                gainNode,
                to: timePitchNode,
                format: floatFormat
            )
            audioEngine.connect(
                timePitchNode,
                to: audioEngine.mainMixerNode,
                format: floatFormat
            )
        }

        // Apply current playback speed
        timePitchNode.rate = playbackSpeed
        timePitchNode.bypass = playbackSpeed == 1.0
        applyVolume(playbackVolumeValue)

        audioEngine.prepare()
    }

    private func applyVolume(_ volume: Float) {
        let clamped = min(maxPlaybackVolume, max(0.0, volume))
        playbackVolumeValue = clamped
        playerNode.volume = min(1.0, clamped)
        if clamped <= 1.0 {
            gainNode.globalGain = 0.0
        } else {
            let db = 20.0 * log10f(clamped)
            gainNode.globalGain = min(24.0, db)
        }
    }

    func enqueue(pcmData: Data) {
        bufferQueue.async { [weak self] in
            guard let self = self, !self.isStopping else { return }

            if !pcmData.isEmpty {
                self.pendingPCMBytes.append(pcmData)
            }

            let bytesPerFrame = Int(self.pcmFormat.streamDescription.pointee.mBytesPerFrame)
            let alignedByteCount = (self.pendingPCMBytes.count / bytesPerFrame) * bytesPerFrame
            guard alignedByteCount > 0 else { return }

            let alignedData = Data(self.pendingPCMBytes.prefix(alignedByteCount))
            self.pendingPCMBytes.removeFirst(alignedByteCount)
            self.enqueueAlignedData(alignedData)
        }
    }

    private func createBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let bytesPerFrame = Int(pcmFormat.streamDescription.pointee.mBytesPerFrame) // 2
        guard data.count % bytesPerFrame == 0 else {
            return nil
        }
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0 else { return nil }

        let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let abl = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var audioBuffer = abl[0]
        let byteCount = frameCount * bytesPerFrame

        // Zero the whole buffer, then copy only what we have
        memset(audioBuffer.mData, 0, Int(audioBuffer.mDataByteSize))
        data.withUnsafeBytes { raw in
            _ = memcpy(audioBuffer.mData, raw.baseAddress!, byteCount)
        }
        audioBuffer.mDataByteSize = UInt32(byteCount)
        abl[0] = audioBuffer

        return buffer
    }

    private func enqueueAlignedData(_ data: Data) {
        // Convert raw bytes to AVAudioPCMBuffer
        guard let buffer = createBuffer(from: data) else {
            print("[Hibiki] ❌ Failed to create audio buffer")
            return
        }

        if !hasStartedPlayback {
            pendingBuffers.append(buffer)
            bufferedSampleCount += Int(buffer.frameLength)
            print("[Hibiki] 🎵 Buffered samples: \(bufferedSampleCount)/\(minimumBufferSize)")

            // Start playback once we have enough buffered
            if bufferedSampleCount >= minimumBufferSize {
                print("[Hibiki] 🎵 Starting playback...")
                startPlayback()
            }
        } else {
            // Schedule buffer immediately if already playing
            scheduleBuffer(buffer)
        }
    }

    private func startPlayback() {
        do {
            if !isEngineRunning {
                print("[Hibiki] 🎵 Starting audio engine...")
                try audioEngine.start()
                isEngineRunning = true
                print("[Hibiki] ✅ Audio engine started")
            }

            // Reset player node to clear any stale state
            playerNode.reset()

            // Schedule a short silent pre-roll buffer to absorb startup noise
            if let silentBuffer = createSilentBuffer(durationMs: 50) {
                playerNode.scheduleBuffer(silentBuffer, completionHandler: nil)
                print("[Hibiki] 🎵 Scheduled silent pre-roll buffer")
            }

            // Schedule all pending buffers
            print("[Hibiki] 🎵 Scheduling \(pendingBuffers.count) pending buffers")
            for buffer in pendingBuffers {
                scheduleBuffer(buffer)
            }
            pendingBuffers.removeAll()

            hasStartedPlayback = true
            if isPaused {
                print("[Hibiki] ⏸️ Playback start deferred (paused)")
                return
            }

            playerNode.play()
            playbackStartTime = Date()
            print("[Hibiki] ✅ Audio playback started")
        } catch {
            print("[Hibiki] ❌ Failed to start audio engine: \(error)")
        }
    }

    /// Creates a silent buffer for pre-roll to absorb engine startup noise
    private func createSilentBuffer(durationMs: Int) -> AVAudioPCMBuffer? {
        let sampleRate = pcmFormat.sampleRate
        let frameCount = UInt32(Double(durationMs) / 1000.0 * sampleRate)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: frameCount
        ) else { return nil }

        buffer.frameLength = frameCount

        // Zero out the buffer (silence)
        let abl = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for index in 0..<abl.count {
            let audioBuffer = abl[index]
            if let mData = audioBuffer.mData {
                memset(mData, 0, Int(audioBuffer.mDataByteSize))
            }
        }

        return buffer
    }

    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        let generation = playbackGeneration
        scheduledBufferCount += 1
        totalScheduledSamples += Int64(buffer.frameLength)
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
            if !self.pendingPCMBytes.isEmpty {
                let bytesPerFrame = Int(self.pcmFormat.streamDescription.pointee.mBytesPerFrame)
                if self.pendingPCMBytes.count % bytesPerFrame != 0 {
                    self.pendingPCMBytes.append(0)
                }
                let aligned = self.pendingPCMBytes
                self.pendingPCMBytes.removeAll()
                self.enqueueAlignedData(aligned)
            }
            if !self.hasStartedPlayback && !self.pendingBuffers.isEmpty {
                print("[Hibiki] 🎵 Stream complete, starting playback with remaining buffers")
                self.startPlayback()
            }
            self.isStreamFinished = true
            if self.totalScheduledSamples > 0 {
                self.estimatedTotalDuration = Double(self.totalScheduledSamples) / self.pcmFormat.sampleRate
            }
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
            self.pendingPCMBytes.removeAll()
            self.bufferedSampleCount = 0
            self.hasStartedPlayback = false
            self.scheduledBufferCount = 0
            self.completedBufferCount = 0
            self.isStreamFinished = false
            self.totalScheduledSamples = 0
            self.playbackStartTime = nil
            self.estimatedTotalDuration = 0
            self.accumulatedVirtualTime = 0
            self.isPaused = false
            self.isStopping = false
        }
    }

    func pause() {
        bufferQueue.sync { [weak self] in
            guard let self = self, !self.isStopping, !self.isPaused else { return }

            if self.hasStartedPlayback, let startTime = self.playbackStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                self.accumulatedVirtualTime += elapsed * Double(self.playbackSpeed)
                self.playbackStartTime = nil
                self.playerNode.pause()
            }
            self.isPaused = true
        }
    }

    func resume() {
        bufferQueue.sync { [weak self] in
            guard let self = self, !self.isStopping, self.isPaused else { return }

            self.isPaused = false
            guard self.hasStartedPlayback else { return }

            if !self.isEngineRunning {
                do {
                    try self.audioEngine.start()
                    self.isEngineRunning = true
                } catch {
                    print("[Hibiki] ❌ Failed to resume audio engine: \(error)")
                }
            }

            self.playerNode.play()
            self.playbackStartTime = Date()
        }
    }

    func reset() {
        stop()
        bufferQueue.sync { [weak self] in
            self?.setupAudioEngine()
        }
    }
}
