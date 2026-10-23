import CoreGraphics
import Foundation

/// Where the second capsule goes, next to the main island. Pure geometry, in panel coordinates
/// with the origin at the top-left.
public enum SatellitePlacement {
    /// Space between the island and the capsule.
    public static let gap: CGFloat = 8
    /// The widest capsule at scale 1; the panel reserves this much on both sides.
    public static let maxWidth: CGFloat = 160

    /// Width at scale 1 by content. A timer or stopwatch under the pointer widens to make room for its buttons.
    public static func baseWidth(for content: ActivityContent, hovering: Bool = false) -> CGFloat {
        switch content {
        case .countdown(let timer): hovering && !timer.isFinished ? maxWidth : 104
        case .stopwatch: hovering ? maxWidth : 104
        case .power: 100
        case .headphones: 112
        case .transfer: 92
        }
    }

    public static func width(for content: ActivityContent, hovering: Bool = false, scale: CGFloat) -> CGFloat {
        (baseWidth(for: content, hovering: hovering) * scale).rounded()
    }

    /// Horizontal space the panel keeps free on each side for the capsule.
    public static func reserve(scale: CGFloat) -> CGFloat {
        ((maxWidth + gap) * scale).rounded(.up)
    }

    /// The capsule sits on the right of the island and follows it as it grows and shrinks.
    /// Without a visible island on a monitor it takes the centre; in the notch it stays beside the notch.
    public static func frame(in layout: IslandLayout, main: ShapeSpec, mainHidden: Bool, width: CGFloat) -> CGRect {
        let height = layout.compact.frame.height
        let top = layout.compact.frame.minY
        // Nothing visible to sit beside: a floating island or a drawn notch whose hidden state is invisible.
        let nothingToSitBeside = layout.style == .floating || layout.hidden.opacity == 0
        let x: CGFloat = if mainHidden && nothingToSitBeside {
            layout.compact.frame.midX - width / 2
        } else {
            main.frame.maxX + main.topFlare + gap
        }
        return CGRect(x: x, y: top, width: width, height: height)
    }
}
