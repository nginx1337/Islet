import AppKit
import SwiftUI

/// Transparent, borderless panel that holds one island.
/// - never becomes key or main and never activates Islet, so the app you work in keeps focus;
/// - sits above the menu bar, joins every Space, ignored by Mission Control and ⌘` cycling;
/// - lets clicks through everywhere except the visible island (see ``IslandController``).
final class IslandPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        setShowsInFullScreen(false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        setAccessibilityLabel("Islet")
    }

    /// Without `.fullScreenAuxiliary` the panel does not appear in full-screen Spaces at all,
    /// which is how "hide in full-screen apps" works at zero cost.
    func setShowsInFullScreen(_ show: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if show { behavior.insert(.fullScreenAuxiliary) }
        collectionBehavior = behavior
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that takes the first click (the panel never becomes key) and reports pointer
/// movement while the pointer is over the panel.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onPointerMoved: (() -> Void)?
    var isInsideShape: ((NSPoint) -> Bool)?
    private var trackingArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointerMoved?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerMoved?()
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        onPointerMoved?()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onPointerMoved?()
    }

    /// Outside the visible shape the view is not there for clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let isInsideShape, let superview {
            let local = convert(point, from: superview)
            let topLeft = NSPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
            if !isInsideShape(topLeft) { return nil }
        }
        return super.hitTest(point)
    }
}
