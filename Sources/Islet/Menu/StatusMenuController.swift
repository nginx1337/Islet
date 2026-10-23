import AppKit
import IsletCore

/// Menu bar icon with: what is playing, pause/resume, settings, quit.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let media: NowPlayingModel
    private let activities: ActivityModel
    private let openSettings: () -> Void

    /// Timer lengths in minutes.
    private static let timerChoices: [Double] = [1, 5, 10, 15, 25, 30, 45, 60]

    init(media: NowPlayingModel, activities: ActivityModel, openSettings: @escaping () -> Void) {
        self.media = media
        self.activities = activities
        self.openSettings = openSettings
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Islet")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Islet"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let state = media.state {
            let header = NSMenuItem(title: state.artist.isEmpty ? state.title : "\(state.title) — \(state.artist)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let toggle = NSMenuItem(
                title: state.isPlaying ? tr("Пауза", "Pause") : tr("Продолжить", "Resume"),
                action: #selector(togglePlayback), keyEquivalent: "")
            toggle.target = self
            menu.addItem(toggle)
        } else {
            let idle = NSMenuItem(title: tr("Сейчас ничего не играет", "Nothing is playing"), action: nil, keyEquivalent: "")
            idle.isEnabled = false
            menu.addItem(idle)
            let toggle = NSMenuItem(title: tr("Пауза", "Pause"), action: nil, keyEquivalent: "")
            toggle.isEnabled = false
            menu.addItem(toggle)
        }
        if media.sourceStatus.isFallback {
            let note = NSMenuItem(title: tr("Запасной режим: Музыка и Spotify", "Fallback mode: Music and Spotify"), action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
        menu.addItem(.separator())
        addTimerItems(to: menu)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: tr("Настройки…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: tr("Выйти из Islet", "Quit Islet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func addTimerItems(to menu: NSMenu) {
        let timerItem = NSMenuItem(title: tr("Таймер", "Timer"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for minutes in Self.timerChoices {
            let item = NSMenuItem(
                title: tr("\(Int(minutes)) мин", "\(Int(minutes)) min"),
                action: #selector(startTimer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            submenu.addItem(item)
        }
        if activities.hasTimer {
            submenu.addItem(.separator())
            let cancel = NSMenuItem(title: tr("Отменить таймер", "Cancel timer"), action: #selector(cancelTimer), keyEquivalent: "")
            cancel.target = self
            submenu.addItem(cancel)
        }
        timerItem.submenu = submenu
        menu.addItem(timerItem)

        let watch = NSMenuItem(
            title: activities.hasStopwatch ? tr("Сбросить секундомер", "Reset stopwatch") : tr("Секундомер", "Stopwatch"),
            action: #selector(startStopwatch), keyEquivalent: "")
        watch.target = self
        menu.addItem(watch)
        if activities.hasStopwatch {
            let stop = NSMenuItem(title: tr("Убрать секундомер", "Remove stopwatch"), action: #selector(removeStopwatch), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Double else { return }
        activities.startTimer(minutes: minutes)
    }

    @objc private func cancelTimer() {
        activities.dismiss(.timer)
    }

    @objc private func startStopwatch() {
        activities.startStopwatch()
    }

    @objc private func removeStopwatch() {
        activities.dismiss(.stopwatch)
    }

    @objc private func togglePlayback() {
        media.perform(.togglePlayPause)
    }

    @objc private func showSettings() {
        openSettings()
    }
}
