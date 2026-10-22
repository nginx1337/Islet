import AppKit
import IsletCore

/// Menu bar icon with: what is playing, pause/resume, settings, quit.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let media: NowPlayingModel
    private let openSettings: () -> Void

    init(media: NowPlayingModel, openSettings: @escaping () -> Void) {
        self.media = media
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
        let settings = NSMenuItem(title: tr("Настройки…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: tr("Выйти из Islet", "Quit Islet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func togglePlayback() {
        media.perform(.togglePlayPause)
    }

    @objc private func showSettings() {
        openSettings()
    }
}
