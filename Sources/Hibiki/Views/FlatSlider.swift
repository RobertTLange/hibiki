import SwiftUI

struct FlatSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var trackHeight: CGFloat = 4
    var thumbDiameter: CGFloat = 12
    var trackColor: Color = Color.secondary.opacity(0.25)
    var fillColor: Color = .accentColor

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let normalized = normalizedValue
            let thumbX = max(0, min(width, width * normalized))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor.opacity(isEnabled ? 1 : 0.5))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(fillColor.opacity(isEnabled ? 1 : 0.5))
                    .frame(width: thumbX, height: trackHeight)

                Circle()
                    .fill(Color.white.opacity(isEnabled ? 0.9 : 0.6))
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(isEnabled ? 0.35 : 0.2), lineWidth: 1)
                    )
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .offset(x: thumbX - thumbDiameter / 2)
            }
            .frame(height: max(trackHeight, thumbDiameter))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(for: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: max(trackHeight, thumbDiameter))
    }

    private var normalizedValue: CGFloat {
        let span = max(0.000_001, range.upperBound - range.lowerBound)
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / span)
    }

    private func updateValue(for xPosition: CGFloat, width: CGFloat) {
        let clampedX = min(max(0, xPosition), width)
        let percent = width > 0 ? Double(clampedX / width) : 0
        let span = range.upperBound - range.lowerBound
        let raw = range.lowerBound + (span * percent)
        value = quantized(raw)
    }

    private func quantized(_ raw: Double) -> Double {
        guard step > 0 else { return raw }
        let steps = (raw - range.lowerBound) / step
        let rounded = steps.rounded()
        let quantizedValue = range.lowerBound + (rounded * step)
        return min(max(quantizedValue, range.lowerBound), range.upperBound)
    }
}
