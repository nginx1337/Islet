import AppKit
import IsletCore
import Observation

/// Wires the app together: sources → media model → islands, plus menu, settings and hotkey.
final class AppModel {
    let settings = AppSettings.shared
    let clock = SystemClock()
    let media: NowPlayingModel
    let islands: IslandCoordinator
    private var statusMenu: StatusMenuController?
    private lazy var settingsWindow = SettingsWindowController(settings: settings, media: media)

    init() {
        let switcher = SourceSwitcher(
            primary: MediaRemoteAdapterSource(), fallback: MusicSpotifySource(), clock: clock)
        media = NowPlayingModel(switcher: switcher)
        media.tintFromArtwork = settings.tintFromArtwork
        islands = IslandCoordinator(media: media, settings: settings, clock: clock)
        media.onStateChange = { [weak self] state in
            self?.islands.mediaChanged(state)
            self?.updateAudio()
        }
    }

    private var audioEnabled = true
    private var audioStop: DispatchWorkItem?

    func start(withMenu: Bool = true) {
        audioEnabled = withMenu
        AudioLevelMonitor.shared.onStatusChange = { AudioStatusModel.shared.status = $0 }
        islands.onPresentationChange = { [weak self] in self?.updateAudio() }
        islands.start()
        media.start()
        if withMenu {
            statusMenu = StatusMenuController(media: media, openSettings: { [weak self] in self?.showSettings() })
        }
        HotKeyCenter.shared.action = { [weak self] in self?.islands.hotkeyPressed() }
        HotKeyCenter.shared.register(settings.hotKey)
        observeSettings()
    }

    func shutdown() {
        AudioLevelMonitor.shared.stop()
        media.stop()
        islands.stop()
    }

    func showSettings() {
        settingsWindow.show()
    }

    /// The audio tap runs only while an island is visible and something plays. Stopping waits
    /// a moment, so a gap between tracks does not rebuild the tap.
    private func updateAudio() {
        let wanted = audioEnabled && settings.liveEqualizer && media.state?.isPlaying == true && islands.anyVisible
        if wanted {
            audioStop?.cancel()
            audioStop = nil
            AudioLevelMonitor.shared.start()
        } else if AudioLevelMonitor.shared.isRunning, audioStop == nil {
            let stop = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.audioStop = nil
                    AudioLevelMonitor.shared.stop()
                }
            }
            audioStop = stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: stop)
        }
    }

    /// Re-applies settings whenever one of them changes.
    private func observeSettings() {
        observeLayoutSettings()
        observeOtherSettings()
    }

    private func observeLayoutSettings() {
        withObservationTracking {
            _ = settings.layoutSettings
            _ = settings.behavior
            _ = settings.showInFullScreen
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.islands.applySettings()
                    self.observeLayoutSettings()
                }
            }
        }
    }

    private func observeOtherSettings() {
        withObservationTracking {
            _ = settings.tintFromArtwork
            _ = settings.hotKey
            _ = settings.liveEqualizer
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.media.tintFromArtwork = self.settings.tintFromArtwork
                    self.updateAudio()
                    if HotKeyCenter.shared.current != self.settings.hotKey {
                        HotKeyCenter.shared.register(self.settings.hotKey)
                    }
                    self.observeOtherSettings()
                }
            }
        }
    }
}
