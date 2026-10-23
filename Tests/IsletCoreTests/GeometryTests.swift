import CoreGraphics
import Testing
@testable import IsletCore

@Suite("Island geometry")
struct GeometryTests {
    /// MacBook Pro 14": 1512×982 points, 32 pt notch, 188 pt wide.
    static let macBook = ScreenDescriptor(
        id: "builtin", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), backingScale: 2,
        safeAreaTop: 32, auxiliaryLeftWidth: 662, auxiliaryRightWidth: 662,
        isBuiltIn: true, isMain: true, statusBarThickness: 24)

    /// 27" 1440p monitor at 1× to the right of the MacBook, top-aligned differently.
    static let monitor1x = ScreenDescriptor(
        id: "dell", frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440), backingScale: 1,
        isBuiltIn: false, isMain: false, statusBarThickness: 24)

    /// Studio Display (5K) in its default 2× "looks like 2560×1440" mode, above the MacBook.
    static let monitor2x = ScreenDescriptor(
        id: "studio", frame: CGRect(x: -500, y: 982, width: 2560, height: 1440), backingScale: 2,
        isBuiltIn: false, isMain: false, statusBarThickness: 24)

    static func isOnPixelGrid(_ value: CGFloat, scale: CGFloat) -> Bool {
        abs((value * scale).rounded() - value * scale) < 0.0001
    }

    // MARK: Style detection

    @Test func notchScreenGetsNotchStyle() {
        #expect(IslandLayoutEngine.style(for: Self.macBook) == .notch)
        #expect(IslandLayoutEngine.style(for: Self.monitor1x) == .floating)
        #expect(Self.macBook.notchRect == CGRect(x: 662, y: 0, width: 188, height: 32))
        #expect(Self.macBook.menuBarHeight == 32)
        #expect(Self.monitor1x.menuBarHeight == 24)
    }

    @Test func menuBarHeightPrefersTheMeasuredBar() {
        // Measured on macOS 27 with a 1440p monitor: thickness 22, real bar 30.
        var screen = Self.monitor1x
        screen.statusBarThickness = 22
        screen.visibleTopInset = 30
        #expect(screen.menuBarHeight == 30)
        screen.visibleTopInset = 0 // auto-hidden menu bar
        #expect(screen.menuBarHeight == 22)
        let below = IslandLayoutEngine.layout(for: { var s = screen; s.visibleTopInset = 30; return s }(), settings: LayoutSettings(placement: .belowMenuBar))
        #expect(below.compact.frame.minY == 36)
    }

    @Test func notchWithoutSideAreasFallsBackToCentredWidth() {
        var screen = Self.macBook
        screen.auxiliaryLeftWidth = nil
        #expect(screen.notchRect?.midX == 756)
    }

    // MARK: Notch layout

    @Test func notchLayoutGrowsOutOfTheNotch() {
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        #expect(layout.style == .notch)
        // Panel hugs the top edge and is centred on the notch.
        #expect(layout.panelFrame.maxY == 982)
        #expect(layout.panelFrame.midX == 756)
        let notchInPanel = layout.panelPoint(fromGlobal: CGPoint(x: 662, y: 982))
        // Hidden: inside the notch.
        #expect(layout.hidden.frame.minX >= notchInPanel.x)
        #expect(layout.hidden.frame.maxX <= notchInPanel.x + 188)
        #expect(layout.hidden.frame.height <= 32)
        #expect(layout.hidden.topFlare == 0)
        // Compact: same height as the notch, with ears on both sides.
        #expect(layout.compact.frame.height == 32)
        #expect(layout.compact.frame.width > 188)
        #expect(layout.compact.frame.midX == layout.hidden.frame.midX)
        #expect(layout.compact.frame.minY == 0, "attached to the top edge")
        #expect(layout.compact.topFlare > 0)
        // Expanded: grows downward and wider, bottom radius ~22.
        #expect(layout.expanded.frame.minY == 0)
        #expect(layout.expanded.frame.height > layout.compact.frame.height + 80)
        #expect(layout.expanded.frame.width > layout.compact.frame.width)
        #expect(layout.expanded.cornerRadius == 22)
        #expect(layout.contentTopInset == 32)
        // Everything fits in the panel, flares included.
        let bounds = CGRect(origin: .zero, size: layout.panelFrame.size)
        for shape in [layout.hidden, layout.compact, layout.expanded] {
            #expect(bounds.contains(shape.hitRect))
        }
    }

    @Test func notchSizeSettingScalesTheExpandedIsland() {
        let normal = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        let big = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings(notchScale: 1.2))
        #expect(big.expanded.frame.width > normal.expanded.frame.width)
        #expect(big.compact.frame.height == 32, "compact height always equals the notch")
        let clamped = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings(notchScale: 9))
        #expect(clamped.scale == 1.5)
    }

    // MARK: Floating layout

    @Test func floatingIslandOverMenuBarAt1x() {
        let layout = IslandLayoutEngine.layout(for: Self.monitor1x, settings: LayoutSettings())
        #expect(layout.style == .floating)
        #expect(layout.panelFrame.maxY == Self.monitor1x.frame.maxY)
        #expect(layout.panelFrame.midX == Self.monitor1x.frame.midX)
        #expect(layout.compact.frame.minY == 6, "6 pt gap from the top edge")
        #expect(layout.compact.cornerRadius == layout.compact.frame.height / 2, "a pill")
        #expect(layout.compact.topFlare == 0)
        // Hidden: a point in the middle of the pill, invisible.
        #expect(layout.hidden.frame.width == 12 && layout.hidden.frame.height == 12, "a dot")
        #expect(layout.hidden.opacity == 0)
        #expect(layout.hidden.frame.midX == layout.compact.frame.midX)
        #expect(layout.hidden.frame.midY == layout.compact.frame.midY)
        // Expanded: same top, wider and taller.
        #expect(layout.expanded.frame.minY == layout.compact.frame.minY)
        #expect(layout.expanded.frame.width > layout.compact.frame.width)
        #expect(layout.expanded.frame.height > layout.compact.frame.height)
        #expect(layout.contentTopInset == 0)
    }

    @Test func floatingIslandBelowMenuBarWithOffset() {
        let settings = LayoutSettings(placement: .belowMenuBar, verticalOffset: 4)
        let layout = IslandLayoutEngine.layout(for: Self.monitor1x, settings: settings)
        #expect(layout.compact.frame.minY == 34, "menu bar 24 + gap 6 + offset 4")
        let up = IslandLayoutEngine.layout(for: Self.monitor1x, settings: LayoutSettings(verticalOffset: -50))
        #expect(up.compact.frame.minY == 6, "never touches the screen edge")
    }

    @Test func floatingIslandOn2xMonitorIsPixelAligned() {
        let settings = LayoutSettings(islandScale: 1.13)
        let layout = IslandLayoutEngine.layout(for: Self.monitor2x, settings: settings)
        for value in [layout.compact.frame.minX, layout.compact.frame.width, layout.expanded.frame.width,
                      layout.expanded.frame.height, layout.panelFrame.minX, layout.panelFrame.width] {
            #expect(Self.isOnPixelGrid(value, scale: 2), "\(value) is on the 2× grid")
        }
        let oneX = IslandLayoutEngine.layout(for: Self.monitor1x, settings: settings)
        for value in [oneX.compact.frame.width, oneX.expanded.frame.width, oneX.panelFrame.minX] {
            #expect(value == value.rounded(), "\(value) is a whole point at 1×")
        }
    }

    @Test func compactTitleWidensTheCompactIsland() {
        let plain = IslandLayoutEngine.layout(for: Self.monitor1x, settings: LayoutSettings())
        let titled = IslandLayoutEngine.layout(for: Self.monitor1x, settings: LayoutSettings(compactTitle: true))
        #expect(titled.compact.frame.width == plain.compact.frame.width + 120)
        #expect(titled.compact.frame.midX == plain.compact.frame.midX, "still centred")
        let notch = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings(compactTitle: true))
        #expect(notch.compact.frame.height == 32)
        #expect(notch.compact.frame.width == IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings()).compact.frame.width + 180)
        #expect(notch.expanded.frame.width > notch.compact.frame.width, "expanding never shrinks it")
        let bounds = CGRect(origin: .zero, size: notch.panelFrame.size)
        #expect(bounds.contains(notch.compact.hitRect))
    }

    @Test func compactWidthFitsTheTitle() {
        let layout = IslandLayoutEngine.layout(for: Self.monitor1x, settings: LayoutSettings(compactTitle: true))
        let short = layout.compact(fittingTitle: 40)
        #expect(short.frame.width == 150, "never narrower than without a title")
        let medium = layout.compact(fittingTitle: 140)
        #expect(medium.frame.width == 236, "two ears of 36 + title 140 + padding 12 + a 6 pt gap on each side")
        #expect(medium.frame.midX == layout.compact.frame.midX, "stays centred")
        #expect(layout.compact(fittingTitle: 900) == layout.compact, "long titles get the full width and scroll")
        #expect(layout.compact(fittingTitle: nil) == layout.compact)
        let plain = IslandLayoutEngine.layout(for: Self.monitor1x, settings: LayoutSettings())
        #expect(plain.compact(fittingTitle: 40) == plain.compact, "no title option, no change")

        let notch = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings(compactTitle: true))
        let fitted = notch.compact(fittingTitle: 50)
        #expect(fitted.frame.width == notch.compactBaseWidth + 2 * (50 + 12))
        #expect(fitted.frame.midX == notch.compact.frame.midX, "centred on the notch")
        #expect(fitted.frame.width < notch.compact.frame.width)
    }

    // MARK: Several screens

    @Test func twoScreensGetTheirOwnStyles() {
        let layouts = IslandLayoutEngine.layouts(for: [Self.macBook, Self.monitor1x], settings: LayoutSettings())
        #expect(layouts.map(\.screenID) == ["builtin", "dell"])
        #expect(layouts.map(\.style) == [.notch, .floating])
        // Each panel stays on its own screen.
        #expect(Self.macBook.frame.contains(layouts[0].panelFrame))
        #expect(Self.monitor1x.frame.contains(layouts[1].panelFrame))
    }

    @Test func screenSelection() {
        let screens = [Self.macBook, Self.monitor1x, Self.monitor2x]
        func ids(_ selection: ScreenSelection) -> [String] {
            IslandLayoutEngine.layouts(for: screens, settings: LayoutSettings(selection: selection)).map(\.screenID)
        }
        #expect(ids(.all) == ["builtin", "dell", "studio"])
        #expect(ids(.main) == ["builtin"])
        #expect(ids(.builtIn) == ["builtin"])
        #expect(ids(.external) == ["dell", "studio"])
        // Lid closed: no built-in screen, so "built-in only" shows nothing.
        #expect(IslandLayoutEngine.layouts(for: [Self.monitor1x], settings: LayoutSettings(selection: .builtIn)).isEmpty)
    }

    @Test func screenConfigurationChanges() {
        let settings = LayoutSettings()
        let before = IslandLayoutEngine.layouts(for: [Self.macBook], settings: settings)
        // Monitor plugged in.
        let plugged = IslandLayoutEngine.layouts(for: [Self.macBook, Self.monitor1x], settings: settings)
        #expect(LayoutChanges.between(before, plugged) == LayoutChanges(added: ["dell"], removed: [], changed: []))
        // Lid closed: the monitor becomes main, the built-in screen disappears.
        var mainMonitor = Self.monitor1x
        mainMonitor.isMain = true
        let lidClosed = IslandLayoutEngine.layouts(for: [mainMonitor], settings: settings)
        #expect(LayoutChanges.between(plugged, lidClosed) == LayoutChanges(added: [], removed: ["builtin"], changed: []))
        // Resolution changed on the monitor.
        var resized = mainMonitor
        resized.frame = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let afterResize = IslandLayoutEngine.layouts(for: [resized], settings: settings)
        #expect(LayoutChanges.between(lidClosed, afterResize).changed == ["dell"])
        #expect(afterResize[0].panelFrame.midX == resized.frame.midX)
        #expect(afterResize[0].panelFrame.maxY == resized.frame.maxY)
        // Nothing changed.
        #expect(LayoutChanges.between(afterResize, afterResize).isEmpty)
    }

    // MARK: Hit testing

    @Test func hitTestFollowsTheVisibleShape() {
        let layout = IslandLayoutEngine.layout(for: Self.monitor1x, settings: LayoutSettings())
        let pill = layout.compact
        #expect(pill.contains(CGPoint(x: pill.frame.midX, y: pill.frame.midY)))
        #expect(!pill.contains(CGPoint(x: pill.frame.minX + 1, y: pill.frame.minY + 1)), "rounded corner")
        #expect(!pill.contains(CGPoint(x: pill.frame.midX, y: pill.frame.maxY + 2)))
        #expect(!layout.hidden.contains(CGPoint(x: pill.frame.midX, y: pill.frame.midY)), "hidden takes no clicks")

        let notch = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings()).expanded
        #expect(notch.contains(CGPoint(x: notch.frame.minX + 1, y: notch.frame.minY + 1)), "square top corners")
        #expect(!notch.contains(CGPoint(x: notch.frame.minX + 1, y: notch.frame.maxY - 1)), "round bottom corners")
        #expect(notch.contains(CGPoint(x: notch.frame.minX - 2, y: 1)), "the flare along the top edge")
        #expect(!notch.contains(CGPoint(x: notch.frame.minX - 2, y: 7)))
    }

    @Test func coordinateConversionRoundTrips() {
        let layout = IslandLayoutEngine.layout(for: Self.monitor2x, settings: LayoutSettings())
        let p = CGPoint(x: 120, y: 40)
        #expect(layout.panelPoint(fromGlobal: layout.globalPoint(fromPanel: p)) == p)
    }

    // MARK: Style preference

    @Test func automaticKeepsTheScreenDefault() {
        let settings = LayoutSettings(stylePreference: .automatic)
        #expect(IslandLayoutEngine.layout(for: Self.macBook, settings: settings).style == .notch)
        #expect(IslandLayoutEngine.layout(for: Self.monitor1x, settings: settings).style == .floating)
    }

    @Test func islandOnAScreenWithANotchSitsBelowTheMenuBar() {
        let settings = LayoutSettings(placement: .overMenuBar, stylePreference: .island)
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: settings)
        #expect(layout.style == .floating)
        #expect(layout.compact.frame.minY >= Self.macBook.safeAreaTop, "never over the physical notch")
        let bounds = CGRect(origin: .zero, size: layout.panelFrame.size)
        for shape in [layout.compact, layout.expanded] {
            #expect(bounds.contains(shape.hitRect))
        }
    }

    @Test func notchOnAMonitorIsDrawnAtTheTopCentre() {
        var monitor = Self.monitor1x
        monitor.visibleTopInset = 30
        let layout = IslandLayoutEngine.layout(for: monitor, settings: LayoutSettings(stylePreference: .notch))
        #expect(layout.style == .notch)
        #expect(layout.panelFrame.maxY == monitor.frame.maxY)
        #expect(layout.panelFrame.midX == monitor.frame.midX)
        #expect(layout.compact.frame.minY == 0, "attached to the top edge")
        #expect(layout.compact.frame.height == 30, "as tall as the menu bar")
        #expect(layout.compact.topFlare > 0)
        #expect(layout.isDrawnNotch)
        #expect(layout.notchWidth == 0, "nothing is hidden in the middle")
        #expect(layout.compact.frame.width < 200, "a compact tab, not a long bar")
        #expect(layout.hidden.opacity == 0, "a drawn notch has nothing to hide in")
        #expect(layout.expanded.frame.height > layout.compact.frame.height + 80)
        let bounds = CGRect(origin: .zero, size: layout.panelFrame.size)
        for shape in [layout.hidden, layout.compact, layout.expanded] {
            #expect(bounds.contains(shape.hitRect))
        }
        #expect(!layout.hidden.contains(CGPoint(x: layout.hidden.frame.midX, y: 1)), "invisible means untouchable")
    }

    @Test func notchPreferenceKeepsTheRealNotchOnAMacBook() {
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings(stylePreference: .notch))
        let automatic = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        #expect(layout == automatic)
        #expect(layout.hidden.opacity == 1)
    }

    @Test func drawnNotchWithTitleStaysShortAndHugsTheTitle() {
        var monitor = Self.monitor1x
        monitor.visibleTopInset = 30
        let layout = IslandLayoutEngine.layout(
            for: monitor, settings: LayoutSettings(compactTitle: true, stylePreference: .notch))
        #expect(layout.compact.frame.width < 330)
        let short = layout.compact(fittingTitle: 30)
        let long = layout.compact(fittingTitle: 500)
        #expect(short.frame.width >= layout.compactBaseWidth)
        #expect(short.frame.width < long.frame.width)
        #expect(long.frame.width == layout.compact.frame.width, "never wider than the widest compact shape")
        #expect(short.frame.midX == layout.compact.frame.midX, "stays centred")
    }
}

