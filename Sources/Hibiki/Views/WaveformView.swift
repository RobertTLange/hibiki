import SwiftUI

struct WaveformView: View {
    let level: Float
    let barCount: Int

    @State private var phases: [Double] = []

    init(level: Float, barCount: Int = 40) {
        self.level = level
        self.barCount = barCount
    }

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: 2.5, height: barHeight(for: index))
            }
        }
        .frame(height: 32)
        .onAppear {
            // Initialize random phases for organic look
            phases = (0..<barCount).map { _ in Double.random(in: 0...Double.pi * 2) }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 32

        // Create a wave pattern that varies across bars
        let normalizedIndex = Double(index) / Double(barCount)

        // Multiple sine waves for organic look
        let phase = phases.indices.contains(index) ? phases[index] : 0
        let wave1 = sin(normalizedIndex * Double.pi * 3 + phase)
        let wave2 = sin(normalizedIndex * Double.pi * 7 + phase * 0.5) * 0.5
        let wave3 = sin(normalizedIndex * Double.pi * 11 + phase * 0.3) * 0.25

        let combinedWave = (wave1 + wave2 + wave3) / 1.75 // Normalize to roughly -1 to 1
        let normalizedWave = (combinedWave + 1) / 2 // Convert to 0-1

        // Scale by audio level
        let levelScale = CGFloat(max(0.1, level)) // Minimum activity
        let height = minHeight + (maxHeight - minHeight) * normalizedWave * levelScale

        return max(minHeight, height)
    }
}

#Preview {
    VStack(spacing: 20) {
        WaveformView(level: 0.0)
        WaveformView(level: 0.3)
        WaveformView(level: 0.6)
        WaveformView(level: 1.0)
    }
    .padding()
    .background(Color.black)
}
