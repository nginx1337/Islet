import Foundation
import IsletCore
import Observation

/// User preferences, stored in UserDefaults. Every change is saved immediately.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    var islandStyle: IslandStylePreference { didSet { save(islandStyle.rawValue, "islandStyle") } }
    var screenSelection: ScreenSelection { didSet { save(screenSelection.rawValue, "screenSelection") } }
    var monitorPlacement: MonitorPlacement { didSet { save(monitorPlacement.rawValue, "monitorPlacement") } }
    var verticalOffset: Double { didSet { save(verticalOffset, "verticalOffset") } }
    var notchScale: Double { didSet { save(notchScale, "notchScale") } }
    var islandScale: Double { didSet { save(islandScale, "islandScale") } }
    var autoHideEnabled: Bool { didSet { save(autoHideEnabled, "autoHideEnabled") } }
    var autoHideSeconds: Double { didSet { save(autoHideSeconds, "autoHideSeconds") } }
    var expandOnHover: Bool { didSet { save(expandOnHover, "expandOnHover") } }
    var expandOnTrackChange: Bool { didSet { save(expandOnTrackChange, "expandOnTrackChange") } }
    var tintFromArtwork: Bool { didSet { save(tintFromArtwork, "tintFromArtwork") } }
    var showInFullScreen: Bool { didSet { save(showInFullScreen, "showInFullScreen") } }
    var compactTitle: Bool { didSet { save(compactTitle, "compactTitle") } }
    var liveEqualizer: Bool { didSet { save(liveEqualizer, "liveEqualizer") } }
    var showPowerActivity: Bool { didSet { save(showPowerActivity, "showPowerActivity") } }
    var showHeadphonesActivity: Bool { didSet { save(showHeadphonesActivity, "showHeadphonesActivity") } }
    /// Off by default: it watches Downloads, Desktop, Documents and mounted volumes.
    var showTransferActivity: Bool { didSet { save(showTransferActivity, "showTransferActivity") } }
    var timerSound: Bool { didSet { save(timerSound, "timerSound") } }
    var hotKey: HotKeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: "hotKey")
            } else {
                defaults.set(Data(), forKey: "hotKey") // empty = turned off
            }
        }
    }
    var language: AppLanguage {
        didSet {
            save(language.rawValue, "language")
            currentLanguage = language.resolved
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        islandStyle = defaults.string(forKey: "islandStyle").flatMap(IslandStylePreference.init) ?? .automatic
        screenSelection = defaults.string(forKey: "screenSelection").flatMap(ScreenSelection.init) ?? .all
        monitorPlacement = defaults.string(forKey: "monitorPlacement").flatMap(MonitorPlacement.init) ?? .overMenuBar
        verticalOffset = defaults.object(forKey: "verticalOffset") as? Double ?? 0
        notchScale = defaults.object(forKey: "notchScale") as? Double ?? 1
        islandScale = defaults.object(forKey: "islandScale") as? Double ?? 1
        autoHideEnabled = defaults.object(forKey: "autoHideEnabled") as? Bool ?? true
        autoHideSeconds = defaults.object(forKey: "autoHideSeconds") as? Double ?? 15
        expandOnHover = defaults.object(forKey: "expandOnHover") as? Bool ?? true
        expandOnTrackChange = defaults.object(forKey: "expandOnTrackChange") as? Bool ?? true
        tintFromArtwork = defaults.object(forKey: "tintFromArtwork") as? Bool ?? true
        showInFullScreen = defaults.object(forKey: "showInFullScreen") as? Bool ?? false
        compactTitle = defaults.object(forKey: "compactTitle") as? Bool ?? false
        liveEqualizer = defaults.object(forKey: "liveEqualizer") as? Bool ?? true
        showPowerActivity = defaults.object(forKey: "showPowerActivity") as? Bool ?? true
        showHeadphonesActivity = defaults.object(forKey: "showHeadphonesActivity") as? Bool ?? true
        showTransferActivity = defaults.object(forKey: "showTransferActivity") as? Bool ?? false
        timerSound = defaults.object(forKey: "timerSound") as? Bool ?? true
        if let data = defaults.data(forKey: "hotKey") {
            hotKey = data.isEmpty ? nil : (try? JSONDecoder().decode(HotKeyCombo.self, from: data))?.normalized()
        } else {
            hotKey = .defaultCombo
        }
        language = defaults.string(forKey: "language").flatMap(AppLanguage.init) ?? .system
        currentLanguage = language.resolved
    }

    var layoutSettings: LayoutSettings {
        LayoutSettings(
            selection: screenSelection, placement: monitorPlacement, verticalOffset: verticalOffset,
            notchScale: notchScale, islandScale: islandScale, compactTitle: compactTitle,
            stylePreference: islandStyle)
    }

    var behavior: IslandBehavior {
        var b = IslandBehavior()
        b.pauseHideDelay = autoHideEnabled ? autoHideSeconds : nil
        b.expandOnHover = expandOnHover
        b.expandOnTrackChange = expandOnTrackChange
        return b
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
