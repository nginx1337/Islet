import AppKit
import IsletCore
import Observation
import SwiftUI

/// What one island view needs besides the shared media model.
@Observable
final class IslandViewModel {
    var layout: IslandLayout
    private(set) var presentation: IslandPresentation = .hidden
    @ObservationIgnored var onClick: (() -> Void)?

    init(layout: IslandLayout) {
        self.layout = layout
    }

    var style: IslandStyle { layout.style }
    var shape: ShapeSpec { layout.shape(for: presentation) }

    func setPresentation(_ new: IslandPresentation, animated: Bool = true) {
        let old = presentation
        guard new != old else { return }
        guard animated else {
            presentation = new
            return
        }
        withAnimation(Self.animation(from: old, to: new, style: layout.style)) {
            presentation = new
        }
    }

    /// Springs: a bouncy pop out of the point (floating), softer morphs for the notch.
    static func animation(from old: IslandPresentation, to new: IslandPresentation, style: IslandStyle) -> Animation {
        switch (old, new) {
        case (.hidden, _) where style == .floating:
            .spring(response: 0.5, dampingFraction: 0.62)
        case (.hidden, _):
            .spring(response: 0.45, dampingFraction: 0.78)
        case (_, .hidden):
            .spring(response: 0.36, dampingFraction: 0.92)
        case (_, .expanded):
            .spring(response: 0.42, dampingFraction: 0.76)
        default:
            .spring(response: 0.38, dampingFraction: 0.86)
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

    init(layout: IslandLayout, media: NowPlayingModel, behavior: IslandBehavior, clock: IslandClock, showInFullScreen: Bool) {
        screenID = layout.screenID
        viewModel = IslandViewModel(layout: layout)
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
            return self.viewModel.shape.contains(point)
        }
        viewModel.onClick = { [weak self] in self?.machine.clicked() }
        machine.onChange = { [weak self] old, new in
            guard let self else { return }
            Log.island.info("\(self.layout.style.rawValue, privacy: .public): \(String(describing: old), privacy: .public) → \(String(describing: new), privacy: .public)")
            self.viewModel.setPresentation(new)
            if new.isHidden { self.setPointerInside(false) }
            self.onPresentationChange?()
        }
        panel.orderFrontRegardless()
    }

    var layout: IslandLayout { viewModel.layout }
    var presentation: IslandPresentation { machine.presentation }

    func apply(layout: IslandLayout) {
        guard layout != viewModel.layout else { return }
        viewModel.layout = layout
        panel.setFrame(layout.panelFrame, display: true)
    }

    func setShowsInFullScreen(_ show: Bool) {
        panel.setShowsInFullScreen(show)
    }

    func mediaChanged(_ state: NowPlayingState?) {
        machine.mediaChanged(state)
    }

    /// Pointer moved anywhere on screen (global AppKit coordinates).
    func pointerMoved(to global: NSPoint) {
        let local = layout.panelPoint(fromGlobal: global)
        var inside = !machine.presentation.isHidden && viewModel.shape.contains(local)
        // While dragging the progress bar the pointer may wander off the island: keep the drag.
        if pointerInside && NSEvent.pressedMouseButtons != 0 { inside = true }
        setPointerInside(inside)
    }

    private func setPointerInside(_ inside: Bool) {
        panel.ignoresMouseEvents = !inside
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
