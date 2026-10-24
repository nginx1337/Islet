import CoreGraphics
import Foundation

/// How a live activity is shown, after the Dynamic Island's presentations.
public enum SatelliteMode: Equatable, Sendable {
    /// Beside the music island: a circle with just a ring or a glyph (Apple's "minimal").
    /// It comes out of the island's edge like a drop.
    case bubble
    /// Nothing else on screen: the activity takes the island's place, glyph left, value right
    /// (Apple's "compact").
    case island
    /// Clicked: a large card in the island's place with the time and big buttons (Apple's "expanded").
    /// It closes when the pointer leaves it.
    case expanded
    /// A short notice (charger, headphones): a card that drops out of the island for a few seconds,
    /// with a large glyph, a title and a subtitle. It only shows the notice: clicks go through it.
    case notice
}

/// What the music island is doing, as far as the activity is concerned.
public enum MainIslandState: Equatable, Sendable {
    case hidden, compact, expanded
}

/// Where a live activity goes. Pure geometry, in panel coordinates with the origin at the top-left.
public enum SatellitePlacement {
    /// Space between the island and the bubble.
    public static let gap: CGFloat = 10
    /// The panel keeps this much free on each side of the expanded island for the bubble (scale 1).
    public static let maxWidth: CGFloat = 136
    /// Width of each side of a real notch that holds the activity in island mode.
    public static let islandEar: CGFloat = 60
    /// Width of the activity island on a screen without a physical notch.
    public static let islandWidth: CGFloat = 150
    /// Size of the notice card below the menu bar or notch (scale 1).
    public static let noticeWidth: CGFloat = 320
    public static let noticeHeight: CGFloat = 72
    /// Height of the expanded activity card below the menu bar or notch (scale 1); it is as wide as
    /// the expanded music island.
    public static let cardHeight: CGFloat = 84

    /// A notice never covers the expanded island (its title and buttons are there): it waits beside it
    /// as a bubble instead. `expanded` is whether the user clicked the activity open.
    public static func mode(for content: ActivityContent, main: MainIslandState, expanded: Bool) -> SatelliteMode {
        switch (content, main) {
        case (.power, .expanded), (.headphones, .expanded): .bubble
        case (.power, _), (.headphones, _): .notice
        default: expanded ? .expanded : (main == .hidden ? .island : .bubble)
        }
    }

    /// Scale for widths whose content is sized from the shape's height. The notch looks keep the height
    /// of the notch or the menu bar whatever the size setting, so these widths must not shrink below
    /// scale 1, or the text would spill under the camera or past the edge.
    static func contentScale(_ layout: IslandLayout) -> CGFloat {
        layout.style == .notch ? max(layout.scale, 1) : layout.scale
    }

    /// Horizontal space the panel keeps free on each side for the bubble.
    public static func reserve(scale: CGFloat) -> CGFloat {
        ((maxWidth + gap) * scale).rounded(.up)
    }

    /// The layout has a physical notch in the middle of the compact island, where nothing can be drawn.
    public static func hasPhysicalNotch(_ layout: IslandLayout) -> Bool {
        layout.style == .notch && !layout.isDrawnNotch && layout.notchWidth > 0
    }

    /// Distance from the right edge of the music island to the bubble's left edge.
    public static func bubbleOffset(from main: ShapeSpec) -> CGFloat {
        main.topFlare + gap
    }

    public static func frame(in layout: IslandLayout, main: ShapeSpec, mode: SatelliteMode) -> CGRect {
        let s = layout.scale
        let height = layout.compact.frame.height
        let top = layout.compact.frame.minY
        func centred(width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: (layout.compact.frame.midX - width / 2).rounded(), y: top, width: width, height: height)
        }
        switch mode {
        case .bubble:
            return CGRect(x: main.frame.maxX + bubbleOffset(from: main), y: top, width: height, height: height)
        case .island:
            let c = contentScale(layout)
            let width = hasPhysicalNotch(layout)
                ? layout.notchWidth + 2 * (islandEar * c).rounded()
                : max(layout.compactBaseWidth, (islandWidth * c).rounded())
            return centred(width: width, height: height)
        case .expanded:
            return centred(
                width: layout.expanded.frame.width,
                height: layout.contentTopInset + (cardHeight * s).rounded())
        case .notice:
            // Never narrower than the island it drops out of (a long compact title makes it wider).
            let width = max((noticeWidth * s).rounded(), main.frame.width, layout.compact.frame.width)
            return centred(width: width, height: layout.contentTopInset + (noticeHeight * s).rounded())
        }
    }
}

extension SatellitePlacement {
    /// The outline an activity is drawn with in a mode (corner radius and the notch flare), shared by
    /// the view and the hit test. Notch looks hang the island and the cards from the top edge.
    public static func shape(of frame: CGRect, mode: SatelliteMode, in layout: IslandLayout) -> ShapeSpec {
        let notchLook = layout.style == .notch
        switch mode {
        case .bubble:
            return ShapeSpec(frame: frame, cornerRadius: frame.height / 2)
        case .island:
            return notchLook
                ? ShapeSpec(frame: frame, cornerRadius: layout.compact.cornerRadius, topFlare: layout.compact.topFlare)
                : ShapeSpec(frame: frame, cornerRadius: frame.height / 2)
        case .expanded, .notice:
            return ShapeSpec(
                frame: frame, cornerRadius: layout.expanded.cornerRadius,
                topFlare: notchLook ? layout.expanded.topFlare : 0)
        }
    }
}

/// SF Symbol for an audio output device, guessed from its name.
public enum DeviceGlyph {
    public static func symbol(forDeviceName name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("homepod") { return "homepod.fill" }
        let speakers = ["speaker", "колонк", "динамик", "jbl", "sonos", "marshall", "soundlink", "boom", "sounddock"]
        if speakers.contains(where: { n.contains($0) }) { return "hifispeaker.fill" }
        return "headphones"
    }
}
