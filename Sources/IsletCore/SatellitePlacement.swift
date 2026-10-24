import CoreGraphics
import Foundation

/// How a live activity is shown, after the Dynamic Island's presentations.
public enum SatelliteMode: Equatable, Sendable {
    /// Beside the music island: a circle with just a ring or a glyph (Apple's "minimal").
    case bubble
    /// The circle widened under the pointer: buttons and the value.
    case capsule
    /// Nothing else on screen: the activity takes the island's place, glyph left, value right
    /// (Apple's "compact").
    case island
    /// A short notice (charger, headphones): the island widens into a banner for a few seconds.
    case banner
}

/// Where a live activity goes. Pure geometry, in panel coordinates with the origin at the top-left.
public enum SatellitePlacement {
    /// Space between the island and the bubble.
    public static let gap: CGFloat = 10
    /// The widest capsule beside the island at scale 1; the panel reserves this much on both sides.
    public static let maxWidth: CGFloat = 136
    /// Width of each side of a real notch that holds the activity (island mode) or the notice (banner).
    public static let islandEar: CGFloat = 60
    public static let bannerEar: CGFloat = 120
    /// Width of the activity island and of the banner on a screen without a physical notch.
    public static let islandWidth: CGFloat = 150
    public static let bannerWidth: CGFloat = 300
    /// Extra room for the pause and cancel buttons when the pointer is on a timer in island mode.
    public static let buttonsWidth: CGFloat = 44

    public static func mode(for content: ActivityContent, mainVisible: Bool, hovering: Bool) -> SatelliteMode {
        switch content {
        case .power, .headphones: .banner
        default: mainVisible ? (hovering ? .capsule : .bubble) : .island
        }
    }

    /// Width of the capsule at scale 1. A timer or stopwatch under the pointer makes room for its buttons.
    public static func baseWidth(for content: ActivityContent, hovering: Bool = false) -> CGFloat {
        switch content {
        case .countdown(let timer): hovering && !timer.isFinished ? maxWidth : 106
        case .stopwatch: hovering ? maxWidth : 106
        case .power: 92
        case .headphones: 116
        case .transfer: 92
        }
    }

    /// Horizontal space the panel keeps free on each side for the capsule.
    public static func reserve(scale: CGFloat) -> CGFloat {
        ((maxWidth + gap) * scale).rounded(.up)
    }

    /// The layout has a physical notch in the middle of the compact island, where nothing can be drawn.
    public static func hasPhysicalNotch(_ layout: IslandLayout) -> Bool {
        layout.style == .notch && !layout.isDrawnNotch && layout.notchWidth > 0
    }

    public static func frame(
        in layout: IslandLayout, main: ShapeSpec, mode: SatelliteMode, content: ActivityContent, hovering: Bool
    ) -> CGRect {
        let s = layout.scale
        let height = layout.compact.frame.height
        let top = layout.compact.frame.minY
        func beside(width: CGFloat) -> CGRect {
            CGRect(x: main.frame.maxX + main.topFlare + gap, y: top, width: width, height: height)
        }
        func centred(width: CGFloat) -> CGRect {
            CGRect(x: (layout.compact.frame.midX - width / 2).rounded(), y: top, width: width, height: height)
        }
        let notch = hasPhysicalNotch(layout)
        switch mode {
        case .bubble:
            return beside(width: height)
        case .capsule:
            return beside(width: (baseWidth(for: content, hovering: hovering) * s).rounded())
        case .island:
            let buttons = hovering && content.hasControls ? (buttonsWidth * s).rounded() : 0
            let base = notch
                ? layout.notchWidth + 2 * (islandEar * s).rounded()
                : max(layout.compactBaseWidth, (islandWidth * s).rounded())
            return centred(width: base + buttons)
        case .banner:
            return centred(width: notch
                ? layout.notchWidth + 2 * (bannerEar * s).rounded()
                : (bannerWidth * s).rounded())
        }
    }
}
