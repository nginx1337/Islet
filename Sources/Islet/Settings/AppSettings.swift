import AppKit
import Foundation
import IsletCore
import Observation

/// Look of Islet's own windows and menus (the island itself is always dark).
enum AppTheme: String, CaseIterable {
    case system, light, dark

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences, stored in UserDefaults. Every change is saved immediately.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Default values, in one place for the first launch and for "Reset".
    enum Default {
        static let islandStyle = IslandStylePreference.automatic
        static let screenSelection = ScreenSelection.all
        static let monitorPlacement = MonitorPlacement.overMenuBar
        static let verticalOffset = 0.0
        static let scale = 1.0
        static let autoHideEnabled = true
        static let autoHideSeconds = 15.0
        static let expandOnHover = true
        static let hoverDelay = 0.0
        static let collapseDelay = 0.4
        static let expandOnTrackChange = true
        static let trackChangeSeconds = 3.0
        static let tintFromArtwork = true
        static let showInFullScreen = false
        static let compactTitle = false
        static let islandOutline = true
        static let liveEqualizer = true
        static let showPowerActivity = true
        static let showChargerNotices = true
        static let showLowBatteryNotice = true
        static let lowBatteryThreshold = 20
        static let showHeadphonesActivity = true
        static let showTransferActivity = false
        static let noticeSeconds = ActivityCenter.defaultNoticeDuration
        static let timerSound = true
        static let timerSoundName = "Glass"
        static let appTheme = AppTheme.system
        static let showMenuBarIcon = true
    }

    /// Ranges of the numeric settings; stored values are kept inside them.
    enum Limits {
        static let verticalOffset: ClosedRange<Double> = -6...40
        static let scale: ClosedRange<Double> = 0.8...1.3
        static let autoHideSeconds: ClosedRange<Double> = 5...300
        static let hoverDelay: ClosedRange<Double> = 0...1
        static let collapseDelay: ClosedRange<Double> = 0.2...2
        static let trackChangeSeconds: ClosedRange<Double> = 1...10
        static let noticeSeconds: ClosedRange<Double> = ActivityCenter.noticeDurationRange
    }

    /// System alert sounds the timer can play (in /System/Library/Sounds).
    static let timerSounds = [
        "Glass", "Ping", "Hero", "Funk", "Submarine", "Tink", "Purr", "Pop", "Blow", "Bottle", "Frog", "Morse",
        "Sosumi", "Basso"
    ]

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
    /// How long the pointer rests on the island before it expands.
    var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    /// How long the island stays open after the pointer leaves.
    var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    var expandOnTrackChange: Bool { didSet { save(expandOnTrackChange, "expandOnTrackChange") } }
    /// How long a new track keeps the island open.
    var trackChangeSeconds: Double { didSet { save(trackChangeSeconds, "trackChangeSeconds") } }
    var tintFromArtwork: Bool { didSet { save(tintFromArtwork, "tintFromArtwork") } }
    var showInFullScreen: Bool { didSet { save(showInFullScreen, "showInFullScreen") } }
    var compactTitle: Bool { didSet { save(compactTitle, "compactTitle") } }
    var islandOutline: Bool { didSet { save(islandOutline, "islandOutline") } }
    var liveEqualizer: Bool { didSet { save(liveEqualizer, "liveEqualizer") } }
    var showPowerActivity: Bool { didSet { save(showPowerActivity, "showPowerActivity") } }
    /// Notices for plugging the charger in and out.
    var showChargerNotices: Bool { didSet { save(showChargerNotices, "showChargerNotices") } }
    /// A notice when the battery runs low.
    var showLowBatteryNotice: Bool { didSet { save(showLowBatteryNotice, "showLowBatteryNotice") } }
    /// Percentage for the low-battery notice; one of ``PowerMonitor/lowThresholdChoices``.
    var lowBatteryThreshold: Int { didSet { save(lowBatteryThreshold, "lowBatteryThreshold") } }
    var showHeadphonesActivity: Bool { didSet { save(showHeadphonesActivity, "showHeadphonesActivity") } }
    /// Off by default: it watches Downloads, Desktop, Documents and mounted volumes.
    var showTransferActivity: Bool { didSet { save(showTransferActivity, "showTransferActivity") } }
    /// How long a power or headphones notice stays.
    var noticeSeconds: Double { didSet { save(noticeSeconds, "noticeSeconds") } }
    var timerSound: Bool { didSet { save(timerSound, "timerSound") } }
    /// One of ``timerSounds``.
    var timerSoundName: String { didSet { save(timerSoundName, "timerSoundName") } }
    var appTheme: AppTheme { didSet { save(appTheme.rawValue, "appTheme") } }
    /// The menu bar icon. Without it, opening Islet again shows the settings.
    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }
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
        islandStyle = defaults.string(forKey: "islandStyle").flatMap(IslandStylePreference.init) ?? Default.islandStyle
        screenSelection = defaults.string(forKey: "screenSelection").flatMap(ScreenSelection.init) ?? Default.screenSelection
        monitorPlacement = defaults.string(forKey: "monitorPlacement").flatMap(MonitorPlacement.init) ?? Default.monitorPlacement
        verticalOffset = Self.number(defaults, "verticalOffset", default: Default.verticalOffset, in: Limits.verticalOffset)
        notchScale = Self.number(defaults, "notchScale", default: Default.scale, in: Limits.scale)
        islandScale = Self.number(defaults, "islandScale", default: Default.scale, in: Limits.scale)
        autoHideEnabled = defaults.object(forKey: "autoHideEnabled") as? Bool ?? Default.autoHideEnabled
        autoHideSeconds = Self.number(defaults, "autoHideSeconds", default: Default.autoHideSeconds, in: Limits.autoHideSeconds)
        expandOnHover = defaults.object(forKey: "expandOnHover") as? Bool ?? Default.expandOnHover
        hoverDelay = Self.number(defaults, "hoverDelay", default: Default.hoverDelay, in: Limits.hoverDelay)
        collapseDelay = Self.number(defaults, "collapseDelay", default: Default.collapseDelay, in: Limits.collapseDelay)
        expandOnTrackChange = defaults.object(forKey: "expandOnTrackChange") as? Bool ?? Default.expandOnTrackChange
        trackChangeSeconds = Self.number(
            defaults, "trackChangeSeconds", default: Default.trackChangeSeconds, in: Limits.trackChangeSeconds)
        tintFromArtwork = defaults.object(forKey: "tintFromArtwork") as? Bool ?? Default.tintFromArtwork
        showInFullScreen = defaults.object(forKey: "showInFullScreen") as? Bool ?? Default.showInFullScreen
        compactTitle = defaults.object(forKey: "compactTitle") as? Bool ?? Default.compactTitle
        islandOutline = defaults.object(forKey: "islandOutline") as? Bool ?? Default.islandOutline
        liveEqualizer = defaults.object(forKey: "liveEqualizer") as? Bool ?? Default.liveEqualizer
        showPowerActivity = defaults.object(forKey: "showPowerActivity") as? Bool ?? Default.showPowerActivity
        showChargerNotices = defaults.object(forKey: "showChargerNotices") as? Bool ?? Default.showChargerNotices
        showLowBatteryNotice = defaults.object(forKey: "showLowBatteryNotice") as? Bool ?? Default.showLowBatteryNotice
        let threshold = defaults.object(forKey: "lowBatteryThreshold") as? Int ?? Default.lowBatteryThreshold
        lowBatteryThreshold = PowerMonitor.lowThresholdChoices.contains(threshold) ? threshold : Default.lowBatteryThreshold
        showHeadphonesActivity = defaults.object(forKey: "showHeadphonesActivity") as? Bool ?? Default.showHeadphonesActivity
        showTransferActivity = defaults.object(forKey: "showTransferActivity") as? Bool ?? Default.showTransferActivity
        noticeSeconds = Self.number(defaults, "noticeSeconds", default: Default.noticeSeconds, in: Limits.noticeSeconds)
        timerSound = defaults.object(forKey: "timerSound") as? Bool ?? Default.timerSound
        let sound = defaults.string(forKey: "timerSoundName") ?? Default.timerSoundName
        timerSoundName = Self.timerSounds.contains(sound) ? sound : Default.timerSoundName
        appTheme = defaults.string(forKey: "appTheme").flatMap(AppTheme.init) ?? Default.appTheme
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? Default.showMenuBarIcon
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
            stylePreference: islandStyle, outline: islandOutline)
    }

    var behavior: IslandBehavior {
        var b = IslandBehavior()
        b.pauseHideDelay = autoHideEnabled ? autoHideSeconds : nil
        b.expandOnHover = expandOnHover
        b.hoverDelay = hoverDelay
        b.collapseDelay = collapseDelay
        b.expandOnTrackChange = expandOnTrackChange
        b.trackChangeDuration = trackChangeSeconds
        return b
    }

    // MARK: Reset, one settings page at a time

    func resetGeneral() {
        appTheme = Default.appTheme
        showMenuBarIcon = Default.showMenuBarIcon
        hotKey = .defaultCombo
        language = .system
    }

    func resetIsland() {
        islandStyle = Default.islandStyle
        islandOutline = Default.islandOutline
        showInFullScreen = Default.showInFullScreen
        screenSelection = Default.screenSelection
        monitorPlacement = Default.monitorPlacement
        verticalOffset = Default.verticalOffset
        notchScale = Default.scale
        islandScale = Default.scale
    }

    func resetNowPlaying() {
        expandOnHover = Default.expandOnHover
        hoverDelay = Default.hoverDelay
        collapseDelay = Default.collapseDelay
        expandOnTrackChange = Default.expandOnTrackChange
        trackChangeSeconds = Default.trackChangeSeconds
        autoHideEnabled = Default.autoHideEnabled
        autoHideSeconds = Default.autoHideSeconds
        compactTitle = Default.compactTitle
        tintFromArtwork = Default.tintFromArtwork
        liveEqualizer = Default.liveEqualizer
    }

    func resetTimer() {
        timerSound = Default.timerSound
        timerSoundName = Default.timerSoundName
    }

    func resetBattery() {
        showPowerActivity = Default.showPowerActivity
        showChargerNotices = Default.showChargerNotices
        showLowBatteryNotice = Default.showLowBatteryNotice
        lowBatteryThreshold = Default.lowBatteryThreshold
        noticeSeconds = Default.noticeSeconds
    }

    func resetHeadphones() {
        showHeadphonesActivity = Default.showHeadphonesActivity
        noticeSeconds = Default.noticeSeconds
    }

    func resetTransfers() {
        showTransferActivity = Default.showTransferActivity
    }

    /// A number from the defaults, kept inside the range the settings window allows: the defaults
    /// can be edited from outside the app (`defaults write`), and NaN or a huge value must not move
    /// the island off screen or break its timers.
    private static func number(_ defaults: UserDefaults, _ key: String, default value: Double, in range: ClosedRange<Double>) -> Double {
        guard let stored = defaults.object(forKey: key) as? Double, stored.isFinite else { return value }
        return min(max(stored, range.lowerBound), range.upperBound)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
