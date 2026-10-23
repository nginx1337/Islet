import AppKit
import IsletCore

/// Keeps one island per selected screen in sync with the display configuration,
/// feeds them media updates and tracks the pointer while any island is visible.
final class IslandCoordinator {
    private let media: NowPlayingModel
    private let activities: ActivityModel
    private let settings: AppSettings
    private let clock: IslandClock
    private(set) var controllers: [String: IslandController] = [:]
    private(set) var layouts: [IslandLayout] = []
    private var globalMonitor: Any?
    /// Watches for the middle click that brings a hidden island back; exists only while hidden.
    private var restoreMonitor: Any?
    /// Middle clicks on Islet's own panels (the island or its capsule) hide the island.
    private var hideMonitor: Any?
    /// The user hid the island with the middle mouse button (or the menu).
    private(set) var isHiddenByUser = false
    /// The island was hidden or shown by the user.
    var onHiddenChange: (() -> Void)?
    private var screenObserver: NSObjectProtocol?
    /// Any island changed what it shows.
    var onPresentationChange: (() -> Void)?

    init(media: NowPlayingModel, activities: ActivityModel, settings: AppSettings, clock: IslandClock) {
        self.media = media
        self.activities = activities
        self.settings = settings
        self.clock = clock
    }

    func start() {
        rebuild()
        // A local monitor sees only events sent to Islet's own windows, so it never reads other apps' clicks.
        hideMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self, event.buttonNumber == 2, !self.isHiddenByUser else { return event }
                let location = NSEvent.mouseLocation
                guard self.controllers.values.contains(where: { $0.isOnIsland(location) }) else { return event }
                self.setHiddenByUser(true)
                return nil
            }
        }
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
        removeRestoreMonitor()
        if let hideMonitor { NSEvent.removeMonitor(hideMonitor) }
        hideMonitor = nil
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
                    layout: layout, media: media, activities: activities, behavior: settings.behavior, clock: clock,
                    showInFullScreen: settings.showInFullScreen)
                controller.onPresentationChange = { [weak self] in self?.updateMonitor() }
                if isHiddenByUser { controller.setSuppressed(true) }
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

    /// Hides every island and capsule until the user shows them again: from the menu, with the hotkey,
    /// or with another middle click where the island was.
    func setHiddenByUser(_ hidden: Bool) {
        guard hidden != isHiddenByUser else { return }
        isHiddenByUser = hidden
        Log.island.info("hidden by user: \(hidden, privacy: .public)")
        for controller in controllers.values { controller.setSuppressed(hidden) }
        if hidden { installRestoreMonitor() } else { removeRestoreMonitor() }
        updateMonitor()
        onHiddenChange?()
    }

    /// A global monitor sees clicks that go to other apps (the hidden panels let every click through).
    /// It reads only the button and the pointer position, and only while the island is hidden.
    private func installRestoreMonitor() {
        guard restoreMonitor == nil else { return }
        restoreMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.buttonNumber == 2 else { return }
                let location = NSEvent.mouseLocation
                if self.controllers.values.contains(where: { $0.isRestoreSpot(location) }) {
                    self.setHiddenByUser(false)
                }
            }
        }
    }

    private func removeRestoreMonitor() {
        if let restoreMonitor { NSEvent.removeMonitor(restoreMonitor) }
        restoreMonitor = nil
    }

    /// Hotkey: the island on the screen under the pointer, otherwise the primary screen's.
    /// While the user has hidden the islands, it brings them back instead.
    func hotkeyPressed() {
        if isHiddenByUser {
            setHiddenByUser(false)
            return
        }
        let mouse = NSEvent.mouseLocation
        let target = controllers.values.first { $0.panel.screen?.frame.contains(mouse) == true }
            ?? layouts.first.flatMap { controllers[$0.screenID] }
        target?.machine.hotkeyPressed()
    }

    var anyVisible: Bool { controllers.values.contains { !$0.presentation.isHidden } }

    /// The second capsule appeared or went away: pointer tracking follows, and every panel re-checks
    /// whether it should take mouse events.
    func activitiesChanged() {
        updateMonitor()
        for controller in controllers.values { controller.refreshSatellite() }
    }

    // MARK: Pointer tracking

    /// A global mouse-moved monitor exists only while an island is visible; hidden islands cost nothing.
    private func updateMonitor() {
        onPresentationChange?()
        if anyVisible || (activities.current != nil && !isHiddenByUser) {
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
