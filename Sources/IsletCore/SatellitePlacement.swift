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
    /// It only shows the notice: clicks go through to whatever is under it.
    case banner
}

/// What the music island is doing, as far as the activity is concerned.
public enum MainIslandState: Equatable, Sendable {
    case hidden, compact, expanded
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

    /// A notice never covers the expanded island (its title and buttons are there): it waits beside it
    /// as a bubble instead.
    public static func mode(for content: ActivityContent, main: MainIslandState, hovering: Bool) -> SatelliteMode {
        switch (content, main) {
        case (.power, .expanded), (.headphones, .expanded): .bubble
        case (.power, _), (.headphones, _): .banner
        case (_, .hidden): .island
        default: hovering ? .capsule : .bubble
        }
    }

    /// Width of the capsule at scale 1. A timer or stopwatch under the pointer makes room for its buttons.
    /// (Notices never widen into a capsule: they are a banner, or a bubble beside the expanded island.)
    public static func baseWidth(for content: ActivityContent, hovering: Bool = false) -> CGFloat {
        switch content {
        case .countdown(let timer): hovering && !timer.isFinished ? maxWidth : 106
        case .stopwatch: hovering ? maxWidth : 106
        case .transfer, .power, .headphones: 92
        }
    }

    /// Scale for widths whose content is sized from the shape's height. The notch looks keep the height
    /// of the notch or the menu bar whatever the size setting, so their widths must not shrink below
    /// scale 1, or the text would spill under the camera or past the edge.
    static func contentScale(_ layout: IslandLayout) -> CGFloat {
        layout.style == .notch ? max(layout.scale, 1) : layout.scale
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
            let c = contentScale(layout)
            let buttons = hovering && content.hasControls ? (buttonsWidth * c).rounded() : 0
            let base = notch
                ? layout.notchWidth + 2 * (islandEar * c).rounded()
                : max(layout.compactBaseWidth, (islandWidth * c).rounded())
            return centred(width: base + buttons)
        case .banner:
            let c = contentScale(layout)
            let base = notch ? layout.notchWidth + 2 * (bannerEar * c).rounded() : (bannerWidth * c).rounded()
            // Never narrower than the island it covers (a long compact title makes the island wider).
            return centred(width: max(base, main.frame.width))
        }
    }
}
