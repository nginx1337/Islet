import AppKit
import IsletCore
import Observation
import SwiftUI

/// What one island view needs besides the shared media model.
@Observable
final class IslandViewModel {
    var layout: IslandLayout
    private(set) var presentation: IslandPresentation = .hidden
    /// Natural width of the current title in the compact font; the compact island hugs it.
    private(set) var titleWidth: CGFloat?
    /// The live activity in the second capsule.
    let activities: ActivityModel
    /// The pointer is on the capsule: a timer shows its buttons.
    var satelliteHovering = false
    /// Hidden by the user (middle click): the island and its capsule are both gone.
    var isSuppressed = false
    @ObservationIgnored var onClick: (() -> Void)?

    init(layout: IslandLayout, activities: ActivityModel = ActivityModel()) {
        self.layout = layout
        self.activities = activities
    }

    /// Where the second capsule is right now, or nil when there is no activity.
    var satelliteFrame: CGRect? {
        guard let activity = activities.current, let mode = satelliteMode else { return nil }
        return SatellitePlacement.frame(
            in: layout, main: shape, mode: mode, content: activity.content, hovering: satelliteHovering)
    }

    /// How the activity is shown: a bubble beside the island, the island itself, or a banner.
    var satelliteMode: SatelliteMode? {
        guard !isSuppressed, let activity = activities.current else { return nil }
        let main: MainIslandState = switch presentation {
        case .hidden: .hidden
        case .compact: .compact
        case .expanded: .expanded
        }
        return SatellitePlacement.mode(for: activity.content, main: main, hovering: satelliteHovering)
    }

    /// Whether the pointer is on the activity. A banner is only a notice: it takes no clicks and no
    /// hover, so the menu bar items under it keep working and the island under it still expands.
    /// Rounded shapes count only inside their outline, not in the empty corners of their frame.
    func satelliteContains(_ point: CGPoint) -> Bool {
        guard let frame = satelliteFrame, let mode = satelliteMode, mode != .banner else { return false }
        let notchShaped = layout.style == .notch && mode == .island
        let radius = notchShaped ? layout.compact.cornerRadius : frame.height / 2
        return ShapeSpec(frame: frame, cornerRadius: radius, topFlare: notchShaped ? layout.compact.topFlare : 0).contains(point)
    }

    var style: IslandStyle { layout.style }
    var shape: ShapeSpec {
        if case .compact = presentation { return compactShape }
        return layout.shape(for: presentation)
    }

    var compactShape: ShapeSpec { layout.compact(fittingTitle: titleWidth) }

    /// Font of the compact title; shared with the view so the measurement matches the drawing.
    static func compactTitleFontSize(for layout: IslandLayout) -> CGFloat {
        max(11, layout.compact.frame.height * 0.42)
    }

    func setTitle(_ title: String?) {
        let width: CGFloat? = title.flatMap { text in
            guard layout.compactTitle, !text.isEmpty else { return nil }
            let font = NSFont.systemFont(ofSize: Self.compactTitleFontSize(for: layout), weight: .semibold)
            return ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        guard width != titleWidth else { return }
        withAnimation(IslandMotion.title) { titleWidth = width }
    }

    func setPresentation(_ new: IslandPresentation, animated: Bool = true) {
        let old = presentation
        guard new != old else { return }
        guard animated else {
            presentation = new
            return
        }
        withAnimation(IslandMotion.shape(from: old, to: new)) {
            presentation = new
        }
    }
}

/// One island on one screen: panel, state machine and pointer handling.
final class IslandController {
    let screenID: String
    let panel: IslandPanel
    let viewModel: IslandViewModel
    let machine: IslandStateMachine
    /// Called after every presentation change (the coordinator turns pointer tracking on or off).
    var onPresentationChange: (() -> Void)?

    private let hostingView: IslandHostingView<IslandRootView>
    private var pointerInside = false

    init(layout: IslandLayout, media: NowPlayingModel, activities: ActivityModel, behavior: IslandBehavior,
         clock: IslandClock, showInFullScreen: Bool) {
        screenID = layout.screenID
        viewModel = IslandViewModel(layout: layout, activities: activities)
        machine = IslandStateMachine(clock: clock, behavior: behavior)
        panel = IslandPanel(frame: layout.panelFrame)
        panel.setShowsInFullScreen(showInFullScreen)
        hostingView = IslandHostingView(rootView: IslandRootView(model: viewModel, media: media))
        hostingView.frame = NSRect(origin: .zero, size: layout.panelFrame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        hostingView.onPointerMoved = { [weak self] in self?.pointerMoved(to: NSEvent.mouseLocation) }
        hostingView.isInsideShape = { [weak self] point in
            guard let self else { return false }
            return self.viewModel.shape.contains(point) || self.viewModel.satelliteContains(point)
        }
        viewModel.onClick = { [weak self] in self?.machine.clicked() }
        machine.onChange = { [weak self] old, new in
            guard let self else { return }
            Log.island.info("\(self.layout.style.rawValue, privacy: .public): \(String(describing: old), privacy: .public) → \(String(describing: new), privacy: .public)")
            self.viewModel.setPresentation(new)
            if new.isHidden { self.setPointerInside(false) }
            self.refreshSatellite()
            self.onPresentationChange?()
        }
        panel.orderFrontRegardless()
    }

    var layout: IslandLayout { viewModel.layout }
    var presentation: IslandPresentation { machine.presentation }

    func apply(layout: IslandLayout) {
        guard layout != viewModel.layout else { return }
        let title = viewModel.titleWidth != nil || layout.compactTitle
        viewModel.layout = layout
        if title { viewModel.setTitle(mediaTitle) }
        panel.setFrame(layout.panelFrame, display: true)
        refreshSatellite()
    }

    /// Hides the island and its capsule until shown again (or shows them).
    func setSuppressed(_ suppressed: Bool) {
        viewModel.isSuppressed = suppressed
        machine.isSuppressed = suppressed
        refreshSatellite()
    }

    /// The pointer is on the visible island or its capsule (global AppKit coordinates).
    func isOnIsland(_ global: NSPoint) -> Bool {
        let local = layout.panelPoint(fromGlobal: global)
        return (!machine.presentation.isHidden && viewModel.shape.contains(local)) || viewModel.satelliteContains(local)
    }

    /// Where a middle click brings a hidden island back: the compact island's place, a little larger.
    func isRestoreSpot(_ global: NSPoint) -> Bool {
        layout.compact.hitRect.insetBy(dx: -12, dy: -6).contains(layout.panelPoint(fromGlobal: global))
    }

    func setShowsInFullScreen(_ show: Bool) {
        panel.setShowsInFullScreen(show)
    }

    /// Title of the last media update (to re-measure when the layout or its scale changes).
    private var mediaTitle: String?

    func mediaChanged(_ state: NowPlayingState?) {
        mediaTitle = state?.title
        viewModel.setTitle(state?.title)
        machine.mediaChanged(state)
    }

    /// Pointer moved anywhere on screen (global AppKit coordinates).
    func pointerMoved(to global: NSPoint) {
        let local = layout.panelPoint(fromGlobal: global)
        var inside = !machine.presentation.isHidden && viewModel.shape.contains(local)
        // While dragging the progress bar the pointer may wander off the island: keep the drag.
        if pointerInside && NSEvent.pressedMouseButtons != 0 { inside = true }
        updateSatellite(local: local)
        setPointerInside(inside)
    }

    /// The capsule appeared, moved or went away: re-check what is under the pointer, so the panel
    /// takes mouse events only over something visible.
    func refreshSatellite() {
        updateSatellite(local: layout.panelPoint(fromGlobal: NSEvent.mouseLocation))
    }

    /// The second capsule is separate: it never expands the island, it only takes clicks.
    private func updateSatellite(local: CGPoint) {
        satelliteInside = viewModel.satelliteContains(local)
        if viewModel.satelliteHovering != satelliteInside { viewModel.satelliteHovering = satelliteInside }
        panel.ignoresMouseEvents = !(pointerInside || satelliteInside)
    }

    private var satelliteInside = false

    private func setPointerInside(_ inside: Bool) {
        panel.ignoresMouseEvents = !(inside || satelliteInside)
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside { machine.pointerEntered() } else { machine.pointerExited() }
    }

    func close() {
        machine.onChange = nil
        panel.orderOut(nil)
        panel.close()
    }
}
