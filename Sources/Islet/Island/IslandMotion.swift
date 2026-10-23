import IsletCore
import SwiftUI

/// Every animation of the island in one place, so the feel can be tuned here and nowhere else.
///
/// The shape moves with short springs that overshoot a little when it grows and settle cleanly when it
/// shrinks, like the real Dynamic Island. Content just fades; nothing blurs, glows or pulses.
enum IslandMotion {
    /// Compact or hidden → expanded.
    static let grow = Animation.spring(duration: 0.46, bounce: 0.22)
    /// Expanded → compact, or the compact width changing.
    static let settle = Animation.spring(duration: 0.38, bounce: 0.1)
    /// Hidden → shown.
    static let appear = Animation.spring(duration: 0.46, bounce: 0.2)
    /// Shown → hidden.
    static let disappear = Animation.spring(duration: 0.32, bounce: 0)
    /// The second capsule coming and going.
    static let satellite = Animation.spring(duration: 0.46, bounce: 0.2)
    /// The capsule's contents swapping (another activity, or buttons appearing).
    static let swap = Animation.easeInOut(duration: 0.2)
    /// The compact title changing length.
    static let title = Animation.smooth(duration: 0.30)
    /// Button press feedback.
    static let press = Animation.spring(duration: 0.18, bounce: 0)

    /// Content appearing: a short fade that starts once the shape has begun to move.
    static func fadeIn(delay: Double = 0.08) -> Animation { .easeOut(duration: 0.16).delay(delay) }
    /// Content leaving: out of the way before the shape shrinks.
    static let fadeOut = Animation.easeIn(duration: 0.08)

    static func shape(from old: IslandPresentation, to new: IslandPresentation) -> Animation {
        switch (old, new) {
        case (.hidden, _): appear
        case (_, .hidden): disappear
        case (_, .expanded): grow
        default: settle
        }
    }
}
