import CoreGraphics
import Foundation

/// Scrolling for titles that do not fit.
///
/// The text is drawn twice, `gap` apart. One cycle: hold at the start for `pause`,
/// then scroll left by `textWidth + gap` at `speed`, which lands exactly on the second copy,
/// so the jump back to 0 is invisible.
public struct Marquee: Equatable, Sendable {
    public var textWidth: CGFloat
    public var containerWidth: CGFloat
    public var speed: CGFloat
    public var gap: CGFloat
    public var pause: TimeInterval

    public init(textWidth: CGFloat, containerWidth: CGFloat, speed: CGFloat = 30, gap: CGFloat = 32, pause: TimeInterval = 1.6) {
        self.textWidth = textWidth
        self.containerWidth = containerWidth
        self.speed = max(1, speed)
        self.gap = gap
        self.pause = max(0, pause)
    }

    /// Text that fits does not move.
    public var isScrolling: Bool { textWidth > containerWidth + 0.5 }

    /// Distance travelled in one cycle.
    public var travel: CGFloat { textWidth + gap }

    public var cycleDuration: TimeInterval {
        isScrolling ? pause + Double(travel / speed) : 0
    }

    /// Horizontal offset (≤ 0) of the first copy, `elapsed` seconds after the marquee started.
    public func offset(at elapsed: TimeInterval) -> CGFloat {
        guard isScrolling, elapsed > 0 else { return 0 }
        let t = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        guard t > pause else { return 0 }
        return -min(travel, CGFloat(t - pause) * speed)
    }
}
