import AppKit
import IsletCore
import Observation

/// Wires the app together: sources → media model → islands, plus menu, settings and hotkey.
final class AppModel {
    let settings = AppSettings.shared
    let clock = SystemClock()
    let media: NowPlayingModel
    let activityCenter: ActivityCenter
    let activities: ActivityModel
    let islands: IslandCoordinator
    private let power = PowerMonitor()
    private let headphones = HeadphonesMonitor()
    private let transfers: TransferMonitor
    private var wakeObserver: NSObjectProtocol?
    private var statusMenu: StatusMenuController?
    private lazy var settingsWindow = SettingsWindowController(settings: settings, media: media)

    init() {
        let switcher = SourceSwitcher(
            primary: MediaRemoteAdapterSource(), fallback: MusicSpotifySource(), clock: clock)
        media = NowPlayingModel(switcher: switcher)
        media.tintFromArtwork = settings.tintFromArtwork
        activityCenter = ActivityCenter(clock: clock)
        activities = ActivityModel(center: activityCenter)
        transfers = TransferMonitor(clock: clock)
        islands = IslandCoordinator(media: media, activities: activities, settings: settings, clock: clock)
        activities.onChange = { [weak self] in self?.islands.activitiesChanged() }
        activityCenter.onTimerFinished = { [weak self] in
            guard self?.settings.timerSound == true else { return }
            (NSSound(named: NSSound.Name("Glass")) ?? NSSound(named: NSSound.Name("Ping")))?.play()
        }
        power.onNotice = { [weak self] info in self?.activityCenter.postNotice(.power(info)) }
        headphones.onConnect = { [weak self] name in self?.activityCenter.postNotice(.headphones(name: name)) }
        transfers.onUpdate = { [weak self] info in
            guard let center = self?.activityCenter else { return }
            if let info { center.update(.transfer(info)) } else { center.remove(.transfer) }
        }
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
            statusMenu = StatusMenuController(
                media: media, activities: activities, openSettings: { [weak self] in self?.showSettings() },
                islandHidden: { [weak self] in self?.islands.isHiddenByUser ?? false },
                setIslandHidden: { [weak self] hidden in self?.islands.setHiddenByUser(hidden) })
        }
        // Timers are deadline based; after sleep the scheduled wake-up may be late, so check on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activityCenter.refresh() }
        }
        applyActivitySettings()
        HotKeyCenter.shared.action = { [weak self] in self?.islands.hotkeyPressed() }
        HotKeyCenter.shared.register(settings.hotKey)
        observeSettings()
    }

    func shutdown() {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        power.stop()
        headphones.stop()
        transfers.stop()
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

    /// Each activity source runs only while its switch is on.
    private func applyActivitySettings() {
        if settings.showPowerActivity { power.start() } else { power.stop() }
        if settings.showHeadphonesActivity { headphones.start() } else { headphones.stop() }
        if settings.showTransferActivity {
            transfers.start()
        } else if transfers.isRunning {
            transfers.stop()
        }
    }

    private func observeOtherSettings() {
        withObservationTracking {
            _ = settings.tintFromArtwork
            _ = settings.hotKey
            _ = settings.liveEqualizer
            _ = settings.showPowerActivity
            _ = settings.showHeadphonesActivity
            _ = settings.showTransferActivity
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.media.tintFromArtwork = self.settings.tintFromArtwork
                    self.updateAudio()
                    self.applyActivitySettings()
                    if HotKeyCenter.shared.current != self.settings.hotKey {
                        HotKeyCenter.shared.register(self.settings.hotKey)
                    }
                    self.observeOtherSettings()
                }
            }
        }
    }
}
