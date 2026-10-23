import Foundation

/// Spreads the analyser's four bands over more bars, like the iPhone's equaliser.
///
/// Each bar samples the band curve at its own position (linear interpolation between neighbouring
/// bands), so a bass hit lifts the left bars, a cymbal the right ones, and neighbours move together.
public enum EqualizerBars {
    /// Number of bars drawn in the island.
    public static let count = 6

    public static func spread(_ levels: [Float], to count: Int = count) -> [Float] {
        guard count > 0 else { return [] }
        guard levels.count > 1 else { return [Float](repeating: levels.first ?? 0, count: count) }
        guard count > 1 else { return [levels.reduce(0, +) / Float(levels.count)] }
        let last = Float(levels.count - 1)
        return (0..<count).map { i in
            let t = Float(i) / Float(count - 1) * last
            let lower = Int(t.rounded(.down))
            let upper = min(lower + 1, levels.count - 1)
            let fraction = t - Float(lower)
            let value = levels[lower] * (1 - fraction) + levels[upper] * fraction
            return value.isFinite ? min(max(value, 0), 1) : 0
        }
    }
}
