import AppKit
import IsletCore
import SwiftUI

/// Settings window (SwiftUI in an AppKit window, since Islet has no Dock icon or main menu).
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let media: NowPlayingModel

    init(settings: AppSettings, media: NowPlayingModel) {
        self.settings = settings
        self.media = media
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, media: media))
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.title = tr("Islet — настройки", "Islet Settings")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let media: NowPlayingModel
    @State private var audio = AudioStatusModel.shared
    @State private var loginItem = LoginItem.isEnabled
    @State private var loginMessage: String?

    var body: some View {
        // Reading the language here redraws the whole form when it changes.
        let _ = settings.language
        Form {
            Section(tr("Экраны", "Displays")) {
                Picker(tr("Вид", "Look"), selection: $settings.islandStyle) {
                    Text(tr("Авто", "Auto")).tag(IslandStylePreference.automatic)
                    Text(tr("Остров", "Island")).tag(IslandStylePreference.island)
                    Text(tr("Чёлка", "Notch")).tag(IslandStylePreference.notch)
                }
                .pickerStyle(.segmented)
                Text(styleNote).font(.caption).foregroundStyle(.secondary)
                Toggle(tr("Тонкая обводка, как на iPhone", "Thin outline, as on the iPhone"), isOn: $settings.islandOutline)
                Picker(tr("Показывать", "Show on"), selection: $settings.screenSelection) {
                    Text(tr("На всех экранах", "All displays")).tag(ScreenSelection.all)
                    Text(tr("Только на основном", "Primary display only")).tag(ScreenSelection.main)
                    Text(tr("Только на встроенном", "Built-in display only")).tag(ScreenSelection.builtIn)
                    Text(tr("Только на внешних", "External displays only")).tag(ScreenSelection.external)
                }
                Picker(tr("Положение острова", "Island position"), selection: $settings.monitorPlacement) {
                    Text(tr("Поверх строки меню", "Over the menu bar")).tag(MonitorPlacement.overMenuBar)
                    Text(tr("Под строкой меню", "Below the menu bar")).tag(MonitorPlacement.belowMenuBar)
                }
                .pickerStyle(.segmented)
                LabeledSlider(title: tr("Смещение вниз", "Move down"), value: $settings.verticalOffset, range: -6...40, step: 1, format: { "\(Int($0)) pt" })
                LabeledSlider(title: tr("Размер чёлки", "Notch size"), value: $settings.notchScale, range: 0.8...1.3, step: 0.05, format: percent)
                LabeledSlider(title: tr("Размер острова", "Island size"), value: $settings.islandScale, range: 0.8...1.3, step: 0.05, format: percent)
            }

            Section(tr("Поведение", "Behaviour")) {
                Toggle(tr("Раскрывать при наведении", "Expand on hover"), isOn: $settings.expandOnHover)
                Toggle(tr("Раскрывать при смене трека на 3 секунды", "Expand for 3 seconds when the track changes"), isOn: $settings.expandOnTrackChange)
                Toggle(tr("Прятать на паузе", "Hide when paused"), isOn: $settings.autoHideEnabled)
                if settings.autoHideEnabled {
                    Stepper(value: $settings.autoHideSeconds, in: 5...300, step: 5) {
                        Text(tr("Через \(Int(settings.autoHideSeconds)) с", "After \(Int(settings.autoHideSeconds)) s"))
                    }
                }
                Toggle(tr("Название в свёрнутом острове", "Title in the compact island"), isOn: $settings.compactTitle)
                Toggle(isOn: $settings.liveEqualizer) {
                    Text(tr("Полоски показывают настоящий звук", "Bars follow the real sound"))
                    Text(audioNote).font(.caption).foregroundStyle(.secondary)
                }
                if settings.liveEqualizer && audio.status == .silent {
                    Button(tr("Открыть настройки конфиденциальности…", "Open Privacy settings…")) {
                        // Privacy & Security → Screen & System Audio Recording.
                        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture")!
                        NSWorkspace.shared.open(url)
                    }
                }
                Toggle(tr("Цвет по обложке", "Colour from artwork"), isOn: $settings.tintFromArtwork)
                Toggle(tr("Показывать в полноэкранных приложениях", "Show in full-screen apps"), isOn: $settings.showInFullScreen)
            }

            Section(tr("Живые активности", "Live activities")) {
                Text(tr(
                    "Вторая капсула рядом с островом, как в Dynamic Island. Таймер и секундомер запускаются из меню в строке меню.",
                    "A second capsule beside the island, like Dynamic Island. Start the timer and stopwatch from the menu bar menu."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(tr("Звук по окончании таймера", "Sound when the timer ends"), isOn: $settings.timerSound)
                Toggle(isOn: $settings.showPowerActivity) {
                    Text(tr("Зарядка: подключение, отключение, низкий заряд", "Power: plugged in, unplugged, low battery"))
                    Text(tr("Только состояние батареи, без разрешений.", "Battery state only, no permissions."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $settings.showHeadphonesActivity) {
                    Text(tr("Bluetooth-наушники стали выходом звука", "Bluetooth headphones became the sound output"))
                    Text(tr("Показывается название устройства. Уровень заряда не читается.", "Shows the device name. The battery level is not read."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $settings.showTransferActivity) {
                    Text(tr("Прогресс копирования и загрузки файлов", "File copy and download progress"))
                    Text(tr("Следит за «Загрузками», «Рабочим столом», «Документами» и подключёнными томами. Только процент, без имён файлов. Экспериментально.", "Watches Downloads, Desktop, Documents and mounted volumes. Percent only, never file names. Experimental."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(tr("Система", "System")) {
                Toggle(tr("Открывать при входе", "Open at login"), isOn: $loginItem)
                    .onChange(of: loginItem) { _, enabled in
                        loginMessage = LoginItem.set(enabled)
                        loginItem = LoginItem.isEnabled || LoginItem.needsApproval
                    }
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.secondary)
                }
                HotKeyRecorder(combo: $settings.hotKey)
                Picker(tr("Язык", "Language"), selection: $settings.language) {
                    Text(tr("Как в системе", "System")).tag(AppLanguage.system)
                    Text("Русский").tag(AppLanguage.ru)
                    Text("English").tag(AppLanguage.en)
                }
            }

            Section(tr("Источник данных", "Data source")) {
                HStack {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText)
                    Spacer()
                    if case .primary = media.sourceStatus {} else {
                        Button(tr("Повторить", "Retry")) { media.retryPrimarySource() }
                    }
                }
            }

            Section {
                Text(tr(
                    "Islet не собирает статистику и не ходит в сеть. Исключение — обложки Spotify в запасном режиме.",
                    "Islet collects nothing and stays offline, except Spotify artwork in fallback mode."))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Islet \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · MIT · mediaremote-adapter © Jonas van den Berg (BSD-3-Clause)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        // Fits a 13" MacBook; the form scrolls if a section grows.
        .frame(width: 480, height: 760)
    }

    private var styleNote: String {
        switch settings.islandStyle {
        case .automatic:
            tr("Чёлка на MacBook с вырезом, отдельный остров на остальных экранах.", "Notch on a MacBook with a notch, a separate island on other screens.")
        case .island:
            tr("Отдельная капсула на всех экранах. На MacBook с вырезом она под строкой меню.", "A separate pill on every screen. On a MacBook with a notch it sits below the menu bar.")
        case .notch:
            tr("«Чёлка» на всех экранах. Где выреза нет, она нарисована сверху по центру.", "The notch look on every screen. Where there is no notch it is drawn at the top centre.")
        }
    }

    private var audioNote: String {
        guard settings.liveEqualizer else {
            return tr("Сейчас просто анимация.", "Decorative animation only.")
        }
        switch audio.status {
        case .live: return tr("Слушает звук Mac (только уровни, звук не меняется).", "Listening to the Mac's sound (levels only, the sound is not changed).")
        case .silent: return tr("Звука нет. Если музыка играет, включите Islet в Конфиденциальность и безопасность → Запись экрана и системного звука → «Только запись системного звука», затем перезапустите Islet.", "No sound. If music is playing, turn Islet on in Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, then restart Islet.")
        case .failed(let why): return tr("Не удалось подключиться к звуку: ", "Could not attach to audio: ") + why
        case .off, .starting: return tr("macOS один раз спросит разрешение на запись системного звука.", "macOS asks once for System Audio Recording permission.")
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    private var statusText: String {
        switch media.sourceStatus {
        case .starting: tr("Запуск…", "Starting…")
        case .primary: tr("Основной: MediaRemote (любой плеер)", "Primary: MediaRemote (any player)")
        case .fallback(let reason): tr("Запасной: Музыка и Spotify", "Fallback: Music and Spotify") + " (\(reason))"
        case .unavailable(let reason): tr("Недоступен", "Unavailable") + " (\(reason))"
        }
    }

    private var statusColor: Color {
        switch media.sourceStatus {
        case .primary: .green
        case .fallback, .starting: .orange
        case .unavailable: .red
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).frame(width: 180)
                Text(format(value)).monospacedDigit().frame(width: 52, alignment: .trailing).foregroundStyle(.secondary)
            }
        }
    }
}

/// Records a global shortcut: click, press keys with ⌘, ⌥ or ⌃; Esc cancels.
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(tr("Раскрыть остров", "Expand the island")) {
            HStack {
                Button(recording ? tr("Нажмите сочетание…", "Press keys…") : (combo?.displayString ?? tr("Не задано", "None"))) {
                    recording ? stopRecording() : startRecording()
                }
                if combo != nil && !recording {
                    Button {
                        combo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Убрать сочетание", "Remove shortcut"))
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            if let new = HotKeyCombo(event: event) {
                combo = new
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyCenter.shared.resume()
        }
    }
}

/// Observable mirror of the audio monitor's status for the settings window.
@Observable
final class AudioStatusModel {
    static let shared = AudioStatusModel()
    var status: AudioLevelMonitor.Status = .off
}
