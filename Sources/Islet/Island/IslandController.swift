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
    /// The live activity beside the island or in its place.
    let activities: ActivityModel
    /// The user clicked the activity open into its card.
    var activityExpanded = false
    /// Hidden by the user (middle click): the island and its activity are both gone.
    var isSuppressed = false
    @ObservationIgnored var onClick: (() -> Void)?
    /// The activity was clicked.
    @ObservationIgnored var onSatelliteClick: (() -> Void)?

    init(layout: IslandLayout, activities: ActivityModel = ActivityModel()) {
        self.layout = layout
        self.activities = activities
    }

    /// How the activity is shown: a bubble beside the island, the island itself, its open card, or a notice.
    var satelliteMode: SatelliteMode? {
        guard !isSuppressed, let activity = activities.current else { return nil }
        let main: MainIslandState = switch presentation {
        case .hidden: .hidden
        case .compact: .compact
        case .expanded: .expanded
        }
        return SatellitePlacement.mode(for: activity.content, main: main, expanded: activityExpanded)
    }

    /// The activity's outline right now (frame, corner radius, notch flare), or nil when there is none.
    var satelliteShape: ShapeSpec? {
        guard let mode = satelliteMode else { return nil }
        let frame = SatellitePlacement.frame(in: layout, main: shape, mode: mode)
        return SatellitePlacement.shape(of: frame, mode: mode, in: layout)
    }

    /// Everything needed to draw the activity as it is now, or nil when there is none.
    var satelliteSnapshot: SatelliteSnapshot? {
        guard let activity = activities.current, let mode = satelliteMode, let spec = satelliteShape else { return nil }
        return SatelliteSnapshot(activity: activity, mode: mode, shape: spec, main: shape, layout: layout)
    }

    /// Activities on their way out, drawn from their last look until their animation ends.
    private(set) var leavingSatellites: [LeavingSatellite] = []
    @ObservationIgnored private var lastSatellite: SatelliteSnapshot?

    /// Called after anything that can change the activity: when another activity (or a notice that
    /// gives way to a bubble) takes its place, the old one is kept to animate out. Both are drawn in
    /// the same frame, so nothing blinks; the old one is dropped when its animation is over.
    func syncSatellite() {
        let now = satelliteSnapshot
        if let last = lastSatellite, last.identity != now?.identity {
            leavingSatellites.removeAll { $0.snapshot.identity == now?.identity }
            // A notice over an island that just opened gets out of its way at once; anything else
            // goes back into the island.
            let leaving = LeavingSatellite(snapshot: last, quick: last.mode == .notice && presentation.isExpanded)
            leavingSatellites.append(leaving)
            let id = leaving.id
            let gone = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.satelliteGone(id) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + leaving.exitDuration + 0.05, execute: gone)
        }
        lastSatellite = now
    }

    func satelliteGone(_ id: UUID) {
        leavingSatellites.removeAll { $0.id == id }
    }

    /// Whether the pointer is on the activity, inside its outline (not in the empty corners of its frame).
    /// A notice takes no clicks and no hover: menu bar items under it keep working and the island under
    /// it still expands.
    func satelliteContains(_ point: CGPoint) -> Bool {
        guard satelliteMode != .notice, let spec = satelliteShape else { return false }
        return spec.contains(point)
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
    private let clock: IslandClock
    private var pointerInside = false
    /// The open activity card closes a moment after the pointer leaves it.
    private var activityCollapse: ScheduledTask?
    /// Which activity the open card belongs to (a different one closes it).
    private var expandedKind: ActivityKind?
    /// The pointer has been on the open card since it opened.
    private var cardVisited = false
    /// A card opened by a click on a spot it does not cover closes after this long if never visited.
    private static let unvisitedCardDelay: TimeInterval = 3

    init(layout: IslandLayout, media: NowPlayingModel, activities: ActivityModel, behavior: IslandBehavior,
         clock: IslandClock, showInFullScreen: Bool) {
        screenID = layout.screenID
        self.clock = clock
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
        viewModel.onSatelliteClick = { [weak self] in self?.satelliteClicked() }
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
        if suppressed { setActivityExpanded(false) }
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
        updateSatellite(local: local)
        // The open activity card lies over the island: under it the island must not expand.
        let onCard = satelliteInside && viewModel.satelliteMode == .expanded
        var inside = !machine.presentation.isHidden && viewModel.shape.contains(local) && !onCard
        // While dragging the progress bar the pointer may wander off the island: keep the drag.
        if pointerInside && NSEvent.pressedMouseButtons != 0 { inside = true }
        setPointerInside(inside)
    }

    /// A click on the bubble or the activity island opens its card; a click on the card closes it.
    private func satelliteClicked() {
        switch viewModel.satelliteMode {
        case .bubble?, .island?: setActivityExpanded(true)
        case .expanded?: setActivityExpanded(false)
        case .notice?, nil: break
        }
    }

    private func setActivityExpanded(_ expanded: Bool) {
        activityCollapse?.cancel()
        activityCollapse = nil
        cardVisited = false
        expandedKind = expanded ? viewModel.activities.current?.kind : nil
        guard viewModel.activityExpanded != expanded else { return }
        // Opening springs out a little; closing settles back into the bubble without wobbling.
        withAnimation(expanded ? IslandMotion.cardOpen : IslandMotion.dismiss) {
            viewModel.activityExpanded = expanded
        }
        refreshSatellite()
    }

    /// The activity appeared, moved, opened or went away: re-check what is under the pointer, so the
    /// panel takes mouse events only over something visible.
    func refreshSatellite() {
        viewModel.syncSatellite()
        updateSatellite(local: layout.panelPoint(fromGlobal: NSEvent.mouseLocation))
    }

    /// The activity is separate from the island: it never expands the island, it takes its own clicks.
    /// Its open card closes with its activity, or a moment after the pointer leaves it.
    private func updateSatellite(local: CGPoint) {
        if viewModel.activityExpanded, viewModel.activities.current?.kind != expandedKind {
            setActivityExpanded(false)
            return
        }
        satelliteInside = viewModel.satelliteContains(local)
        if viewModel.activityExpanded {
            if satelliteInside {
                cardVisited = true
                activityCollapse?.cancel()
                activityCollapse = nil
            } else if activityCollapse == nil {
                let delay = cardVisited ? machine.behavior.collapseDelay : Self.unvisitedCardDelay
                activityCollapse = clock.schedule(after: delay) { [weak self] in
                    self?.activityCollapse = nil
                    self?.setActivityExpanded(false)
                }
            }
        }
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
