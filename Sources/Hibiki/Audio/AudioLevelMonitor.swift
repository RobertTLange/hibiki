import AVFoundation
import Combine

final class AudioLevelMonitor: ObservableObject {
    @Published var currentLevel: Float = 0.0

    private var tapInstalled = false
    private weak var monitoredEngine: AVAudioEngine?

    func startMonitoring(engine: AVAudioEngine) {
        guard !tapInstalled else { return }

        monitoredEngine = engine
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)

        // Install tap to sample audio levels
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let level = self?.calculateLevel(buffer: buffer) ?? 0
            DispatchQueue.main.async {
                self?.currentLevel = level
            }
        }
        tapInstalled = true
    }

    func stopMonitoring() {
        guard tapInstalled, let engine = monitoredEngine else { return }

        engine.mainMixerNode.removeTap(onBus: 0)
        tapInstalled = false
        monitoredEngine = nil

        DispatchQueue.main.async {
            self.currentLevel = 0
        }
    }

    private func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        // Handle different PCM formats
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0

        if let floatData = buffer.floatChannelData {
            // Float32 format
            let channelData = floatData.pointee
            for i in 0..<frameLength {
                let sample = channelData[i]
                sum += sample * sample
            }
        } else if let int16Data = buffer.int16ChannelData {
            // Int16 format - normalize to -1.0 to 1.0
            let channelData = int16Data.pointee
            for i in 0..<frameLength {
                let normalized = Float(channelData[i]) / Float(Int16.max)
                sum += normalized * normalized
            }
        } else {
            return 0
        }

        // Calculate RMS
        let rms = sqrt(sum / Float(frameLength))

        // Normalize to 0-1 range with some amplification for visibility
        // Speech typically has low RMS values, so we amplify
        return min(1.0, rms * 8.0)
    }
}
