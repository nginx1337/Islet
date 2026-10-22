import CoreGraphics
import Foundation

/// Plain data about one display, read from `NSScreen` by the app (or made up in tests).
public struct ScreenDescriptor: Equatable, Sendable {
    public var id: String
    /// Global AppKit coordinates (origin at the bottom-left of the main screen).
    public var frame: CGRect
    public var backingScale: CGFloat
    /// `NSScreen.safeAreaInsets.top`: the notch height, 0 on screens without a notch.
    public var safeAreaTop: CGFloat
    /// Widths of `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (the menu bar on each side of the notch).
    public var auxiliaryLeftWidth: CGFloat?
    public var auxiliaryRightWidth: CGFloat?
    public var isBuiltIn: Bool
    public var isMain: Bool
    /// `NSStatusBar.system.thickness`. Fallback only: on macOS 27 it says 22 pt while the bar is 30 pt.
    public var statusBarThickness: CGFloat
    /// `frame.maxY − visibleFrame.maxY`: the menu bar as actually laid out (0 when it auto-hides).
    public var visibleTopInset: CGFloat

    public init(
        id: String, frame: CGRect, backingScale: CGFloat = 2, safeAreaTop: CGFloat = 0,
        auxiliaryLeftWidth: CGFloat? = nil, auxiliaryRightWidth: CGFloat? = nil,
        isBuiltIn: Bool = false, isMain: Bool = false, statusBarThickness: CGFloat = 24,
        visibleTopInset: CGFloat = 0
    ) {
        self.id = id
        self.frame = frame
        self.backingScale = backingScale
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.statusBarThickness = statusBarThickness
        self.visibleTopInset = visibleTopInset
    }

    public var hasNotch: Bool { safeAreaTop > 0 }

    /// Menu bar height: the notch height where there is one; otherwise the measured menu bar,
    /// or the status bar thickness when the menu bar is hidden and cannot be measured.
    public var menuBarHeight: CGFloat {
        if hasNotch { return safeAreaTop }
        if visibleTopInset > 0 && visibleTopInset < 80 { return visibleTopInset }
        return statusBarThickness
    }

    /// Notch rectangle in screen-local coordinates measured from the top-left corner.
    public var notchRect: CGRect? {
        guard hasNotch else { return nil }
        if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth, left > 0, right > 0,
           left + right < frame.width {
            return CGRect(x: left, y: 0, width: frame.width - left - right, height: safeAreaTop)
        }
        // Notch reported without side areas: assume a centred notch of a typical width.
        let width: CGFloat = 200
        return CGRect(x: (frame.width - width) / 2, y: 0, width: width, height: safeAreaTop)
    }
}

/// On which displays the island appears.
public enum ScreenSelection: String, Codable, CaseIterable, Sendable {
    case all, main, builtIn, external
}

/// Where the floating island sits on a display without a notch.
public enum MonitorPlacement: String, Codable, CaseIterable, Sendable {
    /// Centred on the menu bar (the middle of the menu bar is usually empty).
    case overMenuBar
    /// Just below the menu bar.
    case belowMenuBar
}

public struct LayoutSettings: Equatable, Sendable {
    public var selection: ScreenSelection = .all
    public var placement: MonitorPlacement = .overMenuBar
    /// Extra downward shift of the floating island, in points.
    public var verticalOffset: CGFloat = 0
    public var notchScale: CGFloat = 1
    public var islandScale: CGFloat = 1
    /// Show the title in the compact island (between artwork and equaliser).
    public var compactTitle: Bool = false

    public init(
        selection: ScreenSelection = .all, placement: MonitorPlacement = .overMenuBar,
        verticalOffset: CGFloat = 0, notchScale: CGFloat = 1, islandScale: CGFloat = 1,
        compactTitle: Bool = false
    ) {
        self.selection = selection
        self.placement = placement
        self.verticalOffset = verticalOffset
        self.notchScale = notchScale
        self.islandScale = islandScale
        self.compactTitle = compactTitle
    }
}

public enum IslandStyle: String, Equatable, Sendable {
    /// Lives in the MacBook notch and grows out of it.
    case notch
    /// A separate pill floating near the top of a monitor.
    case floating
}

/// One state of the island shape, in panel coordinates with the origin at the top-left.
public struct ShapeSpec: Equatable, Sendable {
    public var frame: CGRect
    /// Bottom corners (notch style) or all corners (floating style).
    public var cornerRadius: CGFloat
    /// Concave "flare" at the top corners that blends the notch shape into the screen edge.
    /// The flare is drawn outside `frame`. Always 0 for the floating style.
    public var topFlare: CGFloat
    public var opacity: Double

    public init(frame: CGRect, cornerRadius: CGFloat, topFlare: CGFloat = 0, opacity: Double = 1) {
        self.frame = frame
        self.cornerRadius = cornerRadius
        self.topFlare = topFlare
        self.opacity = opacity
    }

    /// Hit area including the flares.
    public var hitRect: CGRect { frame.insetBy(dx: -topFlare, dy: 0) }

    /// Whether a point (panel coordinates, top-left origin) is inside the visible shape.
    public func contains(_ point: CGPoint) -> Bool {
        guard opacity > 0, frame.width > 0, frame.height > 0, hitRect.contains(point) else { return false }
        if !frame.contains(point) {
            // In a flare: only the strip along the top edge belongs to the shape.
            return point.y - frame.minY <= topFlare * 0.5
        }
        let r = min(cornerRadius, frame.width / 2, frame.height / 2)
        guard r > 0 else { return true }
        // Top corners are square when the shape has flares (notch style).
        let roundsTop = topFlare == 0
        let left = point.x < frame.minX + r, right = point.x > frame.maxX - r
        let top = point.y < frame.minY + r, bottom = point.y > frame.maxY - r
        guard (left || right) && (bottom || (top && roundsTop)) else { return true }
        let cx = left ? frame.minX + r : frame.maxX - r
        let cy = bottom ? frame.maxY - r : frame.minY + r
        let dx = point.x - cx, dy = point.y - cy
        return dx * dx + dy * dy <= r * r
    }
}

/// Where the panel goes on one screen and what the island looks like there in each state.
public struct IslandLayout: Equatable, Sendable {
    public var screenID: String
    public var style: IslandStyle
    /// Panel frame in global AppKit coordinates (bottom-left origin).
    public var panelFrame: CGRect
    public var hidden: ShapeSpec
    public var compact: ShapeSpec
    public var expanded: ShapeSpec
    /// Height at the top of the expanded island that is covered by the notch (0 for floating).
    public var contentTopInset: CGFloat
    /// Width of the notch itself; compact content goes into the "ears" on its sides.
    public var notchWidth: CGFloat
    public var scale: CGFloat
    /// The compact island has room for the title.
    public var compactTitle: Bool = false

    public func shape(for presentation: IslandPresentation) -> ShapeSpec {
        switch presentation {
        case .hidden: hidden
        case .compact: compact
        case .expanded: expanded
        }
    }

    /// Converts a panel-local, top-left-origin point to global AppKit coordinates.
    public func globalPoint(fromPanel point: CGPoint) -> CGPoint {
        CGPoint(x: panelFrame.minX + point.x, y: panelFrame.maxY - point.y)
    }

    /// Converts a global AppKit point into panel coordinates (top-left origin).
    public func panelPoint(fromGlobal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - panelFrame.minX, y: panelFrame.maxY - point.y)
    }
}

/// Pure function from screens + settings to panel layouts. Recomputed whenever displays change.
public enum IslandLayoutEngine {
    /// Base sizes at scale 1.
    public enum Metrics {
        public static let expandedWidth: CGFloat = 440
        public static let expandedContentHeight: CGFloat = 112
        public static let notchExpandedRadius: CGFloat = 22
        public static let notchTopFlare: CGFloat = 8
        public static let floatingTopGap: CGFloat = 6
        public static let floatingCompactHeight: CGFloat = 30
        public static let floatingCompactWidth: CGFloat = 150
        /// Extra compact width that holds the title (floating pill).
        public static let compactTitleWidth: CGFloat = 120
        /// Extra width of each notch ear when the title is shown (it sits in the left ear).
        public static let notchTitleEar: CGFloat = 90
        public static let floatingExpandedRadius: CGFloat = 32
        public static let shadowMargin: CGFloat = 36
    }

    public static func selectedScreens(_ screens: [ScreenDescriptor], selection: ScreenSelection) -> [ScreenDescriptor] {
        switch selection {
        case .all: screens
        case .main: screens.filter(\.isMain).prefix(1).map { $0 }
        case .builtIn: screens.filter(\.isBuiltIn)
        case .external: screens.filter { !$0.isBuiltIn }
        }
    }

    public static func layouts(for screens: [ScreenDescriptor], settings: LayoutSettings) -> [IslandLayout] {
        selectedScreens(screens, selection: settings.selection).map { layout(for: $0, settings: settings) }
    }

    public static func style(for screen: ScreenDescriptor) -> IslandStyle {
        screen.hasNotch ? .notch : .floating
    }

    public static func layout(for screen: ScreenDescriptor, settings: LayoutSettings) -> IslandLayout {
        var layout = switch style(for: screen) {
        case .notch: notchLayout(screen, scale: clampScale(settings.notchScale), title: settings.compactTitle)
        case .floating: floatingLayout(screen, settings: settings, scale: clampScale(settings.islandScale))
        }
        layout.compactTitle = settings.compactTitle
        return layout
    }

    static func clampScale(_ value: CGFloat) -> CGFloat { min(max(value, 0.7), 1.5) }

    // MARK: Notch

    static func notchLayout(_ screen: ScreenDescriptor, scale s: CGFloat, title: Bool = false) -> IslandLayout {
        let notch = screen.notchRect!
        let px = PixelGrid(scale: screen.backingScale)
        let h = px.round(notch.height)
        // With a title, each ear widens: the title sits in the left one after the artwork.
        let ear = px.round(max(h, 24) * 1.15 * s + (title ? Metrics.notchTitleEar * s : 0))
        let flare = px.round(Metrics.notchTopFlare)
        let expandedWidth = px.round(max(Metrics.expandedWidth * s, notch.width + 2 * ear + 40))
        let expandedHeight = px.round(h + Metrics.expandedContentHeight * s)
        let margin = Metrics.shadowMargin

        let panelWidth = px.round(expandedWidth + 2 * flare + 2 * margin)
        let panelHeight = px.round(expandedHeight + margin)
        // Centre the panel on the notch, not on the screen: notches may be off-centre on future hardware.
        let notchMidX = screen.frame.minX + notch.midX
        let panelFrame = CGRect(
            x: px.round(notchMidX - panelWidth / 2), y: screen.frame.maxY - panelHeight,
            width: panelWidth, height: panelHeight)
        let cx = notchMidX - panelFrame.minX

        func centred(width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: px.round(cx - width / 2), y: 0, width: width, height: height)
        }
        // Hidden: tucked just inside the physical notch, so nothing shows around it.
        let hidden = ShapeSpec(
            frame: centred(width: max(0, notch.width - 4), height: max(0, h - 1)),
            cornerRadius: min(10, h / 3), topFlare: 0)
        let compact = ShapeSpec(
            frame: centred(width: notch.width + 2 * ear, height: h),
            cornerRadius: px.round(min(h * 0.42, 14)), topFlare: flare)
        let expanded = ShapeSpec(
            frame: centred(width: expandedWidth, height: expandedHeight),
            cornerRadius: px.round(Metrics.notchExpandedRadius * s), topFlare: flare)

        return IslandLayout(
            screenID: screen.id, style: .notch, panelFrame: panelFrame,
            hidden: hidden, compact: compact, expanded: expanded,
            contentTopInset: h, notchWidth: notch.width, scale: s)
    }

    // MARK: Floating

    static func floatingLayout(_ screen: ScreenDescriptor, settings: LayoutSettings, scale s: CGFloat) -> IslandLayout {
        let px = PixelGrid(scale: screen.backingScale)
        let menuBar = px.round(screen.menuBarHeight)
        let gap = Metrics.floatingTopGap
        let baseTop: CGFloat = switch settings.placement {
        case .overMenuBar: gap
        case .belowMenuBar: menuBar + gap
        }
        let top = px.round(max(gap, baseTop + settings.verticalOffset))
        let compactHeight = px.round(Metrics.floatingCompactHeight * s)
        let compactWidth = px.round((Metrics.floatingCompactWidth + (settings.compactTitle ? Metrics.compactTitleWidth : 0)) * s)
        let expandedWidth = px.round(Metrics.expandedWidth * s)
        let expandedHeight = px.round(Metrics.expandedContentHeight * s)
        let margin = Metrics.shadowMargin

        let panelWidth = px.round(expandedWidth + 2 * margin)
        let panelHeight = px.round(top + expandedHeight + margin)
        let panelFrame = CGRect(
            x: px.round(screen.frame.midX - panelWidth / 2), y: screen.frame.maxY - panelHeight,
            width: panelWidth, height: panelHeight)
        let cx = screen.frame.midX - panelFrame.minX

        let compactFrame = CGRect(x: px.round(cx - compactWidth / 2), y: top, width: compactWidth, height: compactHeight)
        // Hidden: a small dot in the middle of the pill; the island pops out of it and shrinks back into it.
        let dot = px.round(compactHeight * 0.4)
        let hidden = ShapeSpec(
            frame: CGRect(x: compactFrame.midX - dot / 2, y: compactFrame.midY - dot / 2, width: dot, height: dot),
            cornerRadius: dot / 2, opacity: 0)
        let compact = ShapeSpec(frame: compactFrame, cornerRadius: compactHeight / 2)
        let expanded = ShapeSpec(
            frame: CGRect(x: px.round(cx - expandedWidth / 2), y: top, width: expandedWidth, height: expandedHeight),
            cornerRadius: px.round(Metrics.floatingExpandedRadius * s))

        return IslandLayout(
            screenID: screen.id, style: .floating, panelFrame: panelFrame,
            hidden: hidden, compact: compact, expanded: expanded,
            contentTopInset: 0, notchWidth: 0, scale: s)
    }
}

/// What changed between two layout sets (panels to create, remove and move).
public struct LayoutChanges: Equatable, Sendable {
    public var added: [String]
    public var removed: [String]
    public var changed: [String]

    public static func between(_ old: [IslandLayout], _ new: [IslandLayout]) -> LayoutChanges {
        let oldByID = Dictionary(old.map { ($0.screenID, $0) }, uniquingKeysWith: { a, _ in a })
        let newIDs = Set(new.map(\.screenID))
        return LayoutChanges(
            added: new.map(\.screenID).filter { oldByID[$0] == nil },
            removed: old.map(\.screenID).filter { !newIDs.contains($0) },
            changed: new.filter { layout in oldByID[layout.screenID].map { $0 != layout } ?? false }.map(\.screenID))
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
}

/// Rounds to the physical pixel grid so edges stay crisp at 1× and 2×.
struct PixelGrid {
    let scale: CGFloat
    func round(_ value: CGFloat) -> CGFloat {
        let s = max(scale, 1)
        return (value * s).rounded() / s
    }
}
