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
    @ObservationIgnored var onClick: (() -> Void)?

    init(layout: IslandLayout, activities: ActivityModel = ActivityModel()) {
        self.layout = layout
        self.activities = activities
    }

    /// Where the second capsule is right now, or nil when there is no activity.
    var satelliteFrame: CGRect? {
        guard let activity = activities.current else { return nil }
        let width = SatellitePlacement.width(for: activity.content, scale: layout.scale)
        return SatellitePlacement.frame(in: layout, main: shape, mainHidden: presentation.isHidden, width: width)
    }

    func satelliteContains(_ point: CGPoint) -> Bool {
        satelliteFrame.map { $0.contains(point) } ?? false
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
