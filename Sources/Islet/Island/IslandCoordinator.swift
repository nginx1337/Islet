import AppKit
import IsletCore

/// Keeps one island per selected screen in sync with the display configuration,
/// feeds them media updates and tracks the pointer while any island is visible.
final class IslandCoordinator {
    private let media: NowPlayingModel
    private let settings: AppSettings
    private let clock: IslandClock
    private(set) var controllers: [String: IslandController] = [:]
    private(set) var layouts: [IslandLayout] = []
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    /// Any island changed what it shows.
    var onPresentationChange: (() -> Void)?

    init(media: NowPlayingModel, settings: AppSettings, clock: IslandClock) {
        self.media = media
        self.settings = settings
        self.clock = clock
    }

    func start() {
        rebuild()
        // Monitor plugged in or out, lid closed, resolution or arrangement changed.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        removeMonitor()
        controllers.values.forEach { $0.close() }
        controllers.removeAll()
    }

    /// Recomputes layouts and creates, moves or removes panels.
    func rebuild() {
        let descriptors = ScreenReader.descriptors()
        let newLayouts = IslandLayoutEngine.layouts(for: descriptors, settings: settings.layoutSettings)
        let changes = LayoutChanges.between(layouts, newLayouts)
        layouts = newLayouts
        guard !changes.isEmpty else { return }
        Log.island.info("screens: \(descriptors.count), islands: \(newLayouts.map { "\($0.style.rawValue)" }.joined(separator: ","), privacy: .public)")

        for id in changes.removed {
            controllers.removeValue(forKey: id)?.close()
        }
        for layout in newLayouts {
            if let controller = controllers[layout.screenID] {
                controller.apply(layout: layout)
            } else {
                let controller = IslandController(
                    layout: layout, media: media, behavior: settings.behavior, clock: clock,
                    showInFullScreen: settings.showInFullScreen)
                controller.onPresentationChange = { [weak self] in self?.updateMonitor() }
                controllers[layout.screenID] = controller
                controller.mediaChanged(media.state)
            }
        }
        updateMonitor()
    }

    func applySettings() {
        for controller in controllers.values {
            controller.machine.behavior = settings.behavior
            controller.setShowsInFullScreen(settings.showInFullScreen)
        }
        rebuild()
    }

    func mediaChanged(_ state: NowPlayingState?) {
        for controller in controllers.values { controller.mediaChanged(state) }
    }

    /// Hotkey: the island on the screen under the pointer, otherwise the primary screen's.
    func hotkeyPressed() {
        let mouse = NSEvent.mouseLocation
        let target = controllers.values.first { $0.panel.screen?.frame.contains(mouse) == true }
            ?? layouts.first.flatMap { controllers[$0.screenID] }
        target?.machine.hotkeyPressed()
    }

    var anyVisible: Bool { controllers.values.contains { !$0.presentation.isHidden } }

    // MARK: Pointer tracking

    /// A global mouse-moved monitor exists only while an island is visible; hidden islands cost nothing.
    private func updateMonitor() {
        onPresentationChange?()
        if anyVisible {
            guard globalMonitor == nil else { return }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            }
            pointerMoved()
        } else {
            removeMonitor()
        }
    }

    private func removeMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        for controller in controllers.values { controller.pointerMoved(to: location) }
    }
}
