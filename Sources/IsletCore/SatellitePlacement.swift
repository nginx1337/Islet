import CoreGraphics
import Foundation

/// Where the second capsule goes, next to the main island. Pure geometry, in panel coordinates
/// with the origin at the top-left.
public enum SatellitePlacement {
    /// Space between the island and the capsule.
    public static let gap: CGFloat = 8
    /// The widest capsule at scale 1; the panel reserves this much on both sides.
    public static let maxWidth: CGFloat = 120

    /// Width at scale 1 by content.
    public static func baseWidth(for content: ActivityContent) -> CGFloat {
        switch content {
        case .countdown, .stopwatch: maxWidth
        case .power: 84
        case .headphones: 98
        case .transfer: 92
        }
    }

    public static func width(for content: ActivityContent, scale: CGFloat) -> CGFloat {
        (baseWidth(for: content) * scale).rounded()
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
