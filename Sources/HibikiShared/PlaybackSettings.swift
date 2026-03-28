import Foundation

public enum PlaybackSettings {
    public static let speedRange: ClosedRange<Double> = 1.0...2.5
    public static let speedStep: Double = 0.1

    public static func clampedSpeed(_ speed: Double) -> Double {
        min(speedRange.upperBound, max(speedRange.lowerBound, speed))
    }

    public static func clampedVolume(_ volume: Double, maxVolume: Double = 3.0) -> Double {
        min(maxVolume, max(0.0, volume))
    }

    public static func speedLabel(for speed: Double) -> String {
        String(format: "%.1fx", clampedSpeed(speed))
    }
}
