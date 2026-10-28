import AppKit
import IsletCore
import SwiftUI

// The pages of the settings window. Every page is a grouped form: a section per topic, a coloured
// icon and a grey explanation on each row.

// MARK: - General

struct GeneralPage: View {
    @Bindable var settings: AppSettings
    @State private var loginItem = LoginItem.isEnabled
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section(tr("Система", "System")) {
                ToggleRow(
                    symbol: "power", color: .red, title: tr("Открывать при входе", "Open at login"),
                    subtitle: tr("Запускать Islet при входе в систему.", "Start Islet when you log in."),
                    isOn: $loginItem)
                    .onChange(of: loginItem) { _, enabled in
                        guard enabled != (LoginItem.isEnabled || LoginItem.needsApproval) else { return }
                        loginMessage = LoginItem.set(enabled)
                        loginItem = LoginItem.isEnabled || LoginItem.needsApproval
                    }
                if let loginMessage {
                    Text(loginMessage).font(.caption).foregroundStyle(.secondary)
                }
                ToggleRow(
                    symbol: "menubar.rectangle", color: .blue, title: tr("Значок в строке меню", "Menu bar icon"),
                    subtitle: tr(
                        "Меню с плеером, таймером и настройками. Без значка настройки открываются, если запустить Islet ещё раз.",
                        "A menu with the player, the timer and the settings. Without it, open Islet again to get the settings."),
                    isOn: $settings.showMenuBarIcon)
                LabeledContent {
                    HotKeyField(combo: $settings.hotKey)
                } label: {
                    RowLabel(
                        symbol: "keyboard", color: .gray, title: tr("Сочетание клавиш", "Shortcut"),
                        subtitle: tr("Раскрывает и сворачивает остров; возвращает спрятанный.", "Expands and collapses the island; brings a hidden one back."))
                }
                LabeledContent {
                    Picker(tr("Язык", "Language"), selection: $settings.language) {
                        Text(tr("Как в системе", "System")).tag(AppLanguage.system)
                        Text("Русский").tag(AppLanguage.ru)
                        Text("English").tag(AppLanguage.en)
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    RowLabel(symbol: "globe", color: .blue, title: tr("Язык", "Language"))
                }
            }

            Section(tr("Внешний вид", "Appearance")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        RowLabel(
                            title: tr("Тема", "Theme"),
                            subtitle: tr("Окна и меню Islet. Сам остров всегда чёрный.", "Islet's windows and menus. The island itself is always black."))
                        Spacer()
                        Text(themeName(settings.appTheme)).foregroundStyle(.secondary)
                    }
                    ChoiceCards(selection: $settings.appTheme, options: AppTheme.allCases, label: themeName) { theme, _ in
                        ThemeThumbnail(theme: theme)
                    }
                }
            }

            Section(tr("Спрятать остров", "Hiding the island")) {
                RowLabel(
                    symbol: "computermouse.fill", color: .gray, title: tr("Щелчок колёсиком мыши", "Mouse wheel click"),
                    subtitle: tr(
                        "Щелчок колёсиком по острову прячет его вместе с капсулой. Вернуть: снова колёсиком на том же месте, сочетанием клавиш или «Показать остров» в меню.",
                        "A wheel click on the island hides it and its capsule. Bring it back with another wheel click there, the shortcut, or \"Show the island\" in the menu."))
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem = LoginItem.isEnabled || LoginItem.needsApproval }
    }

    private func themeName(_ theme: AppTheme) -> String {
        switch theme {
        case .system: tr("Как в системе", "System")
        case .light: tr("Светлая", "Light")
        case .dark: tr("Тёмная", "Dark")
        }
    }
}

// MARK: - Permissions

struct PermissionsPage: View {
    let settings: AppSettings
    let media: NowPlayingModel
    @State private var audio = AudioStatusModel.shared

    var body: some View {
        Form {
            Section(tr("Используется", "In use")) {
                LabeledContent {
                    HStack(spacing: 10) {
                        StatusBadge(text: sourceState, color: sourceColor)
                        if case .primary = media.sourceStatus {} else {
                            Button(tr("Повторить", "Retry")) { media.retryPrimarySource() }
                        }
                    }
                } label: {
                    RowLabel(
                        symbol: "music.note", color: .pink, title: tr("Что играет", "Now playing"),
                        subtitle: sourceNote)
                }
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 6) {
                        StatusBadge(text: audioState, color: audioColor)
                        if settings.liveEqualizer && audio.status == .silent {
                            Button(tr("Открыть настройки…", "Open Settings…")) { openAudioPrivacy() }
                        }
                    }
                } label: {
                    RowLabel(
                        symbol: "waveform", color: .red, title: tr("Запись системного звука", "System audio recording"),
                        subtitle: tr(
                            "Только для полосок эквалайзера: считаются уровни четырёх полос частот, звук не записывается и не сохраняется. Можно не давать — полоски просто анимируются.",
                            "Only for the equaliser bars: the levels of four frequency bands, nothing is recorded or stored. You can refuse it; the bars then just animate."))
                }
            }

            Section(tr("Не используется", "Not used")) {
                RowLabel(
                    symbol: "network", color: .blue, title: tr("Сеть", "Network"),
                    subtitle: tr("Islet не ходит в сеть и ничего не отправляет. Исключение — обложки Spotify в запасном режиме.", "Islet stays offline and sends nothing, except Spotify artwork in fallback mode."))
                RowLabel(
                    symbol: "keyboard", color: .gray, title: tr("Клавиатура", "Keyboard"),
                    subtitle: tr("Только своё сочетание клавиш через системный API. Нажатия в других программах не читаются.", "Only its own shortcut, through the system API. Keys typed in other apps are never read."))
                RowLabel(
                    symbol: "headphones", color: .blue, title: "Bluetooth",
                    subtitle: tr("Не нужен: наушники видны по выходу звука. Заряд AirPods не читается.", "Not needed: headphones are seen as the sound output. The AirPods battery is not read."))
                RowLabel(
                    symbol: "folder.fill", color: .purple, title: tr("Файлы", "Files"),
                    subtitle: tr("Только процент копирования и загрузки, если это включено. Имена и содержимое файлов не читаются.", "Only the percent of copies and downloads, when turned on. File names and contents are never read."))
                RowLabel(
                    symbol: "chart.bar.fill", color: .green, title: tr("Статистика", "Analytics"),
                    subtitle: tr("Не собирается.", "None is collected."))
            }
        }
        .formStyle(.grouped)
    }

    private func openAudioPrivacy() {
        // Privacy & Security → Screen & System Audio Recording.
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private var sourceState: String {
        switch media.sourceStatus {
        case .starting: tr("Запуск…", "Starting…")
        case .primary: tr("Работает", "Working")
        case .fallback: tr("Запасной режим", "Fallback")
        case .unavailable: tr("Недоступно", "Unavailable")
        }
    }

    private var sourceColor: Color {
        switch media.sourceStatus {
        case .primary: .green
        case .fallback, .starting: .orange
        case .unavailable: .red
        }
    }

    private var sourceNote: String {
        switch media.sourceStatus {
        case .fallback(let reason):
            tr("Работают только «Музыка» и Spotify (\(reason)).", "Only Music and Spotify work (\(reason)).")
        case .unavailable(let reason):
            tr("Не удалось узнать, что играет (\(reason)).", "Could not tell what is playing (\(reason)).")
        case .starting, .primary:
            tr("Системный MediaRemote через подписанный Apple /usr/bin/perl. Отдельное разрешение не нужно.", "The system MediaRemote, through the Apple-signed /usr/bin/perl. No permission needed.")
        }
    }

    private var audioState: String {
        guard settings.liveEqualizer else { return tr("Выключено", "Off") }
        switch audio.status {
        case .live: return tr("Работает", "Working")
        case .silent: return tr("Нет доступа", "No access")
        case .failed: return tr("Ошибка", "Error")
        case .off, .starting: return tr("Не запрошено", "Not asked yet")
        }
    }

    private var audioColor: Color {
        guard settings.liveEqualizer else { return .gray }
        switch audio.status {
        case .live: return .green
        case .silent, .off, .starting: return .orange
        case .failed: return .red
        }
    }
}

// MARK: - About

struct AboutPage: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Islet").font(.title2.weight(.semibold))
                        Text(tr("Версия ", "Version ") + version).foregroundStyle(.secondary)
                        Text(tr("«Сейчас играет» в виде острова у верхнего края экрана.", "Now Playing as an island at the top of the screen."))
                            .font(.callout)
                    }
                }
                .padding(.vertical, 6)
            }
            Section(tr("Конфиденциальность", "Privacy")) {
                RowLabel(
                    symbol: "lock.fill", color: .blue, title: tr("Ничего не собирается", "Nothing is collected"),
                    subtitle: tr(
                        "Islet не собирает статистику и не ходит в сеть. Исключение — обложки Spotify в запасном режиме. Подробнее — в разделе «Разрешения».",
                        "Islet collects nothing and stays offline, except Spotify artwork in fallback mode. See Permissions for details."))
            }
            Section(tr("Лицензии", "Licenses")) {
                LabeledContent("Islet", value: "MIT")
                LabeledContent("mediaremote-adapter © Jonas van den Berg", value: "BSD-3-Clause")
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

// MARK: - Island and notch

struct IslandPage: View {
    @Bindable var settings: AppSettings
    let media: NowPlayingModel

    var body: some View {
        Form {
            Section {
                IslandPreview(settings: settings, media: media, expanded: false)
            }

            Section(tr("Вид", "Look")) {
                VStack(alignment: .leading, spacing: 10) {
                    ChoiceCards(
                        selection: $settings.islandStyle, options: [.automatic, .island, .notch], label: lookName
                    ) { style, _ in
                        LookThumbnail(style: style)
                    }
                    Text(styleNote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ToggleRow(
                    symbol: "circle.dashed", color: .gray, title: tr("Тонкая обводка", "Thin outline"),
                    subtitle: tr("Едва заметный светлый край, как у iPhone на тёмных обоях.", "A faint light edge, as on the iPhone over a dark wallpaper."),
                    isOn: $settings.islandOutline)
                ToggleRow(
                    symbol: "arrow.up.left.and.arrow.down.right", color: .teal,
                    title: tr("В полноэкранных приложениях", "In full-screen apps"),
                    subtitle: tr("Показывать остров и поверх программ на весь экран.", "Show the island over full-screen apps too."),
                    isOn: $settings.showInFullScreen)
            }

            Section(tr("Дисплей", "Display")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        RowLabel(title: tr("Где показывать", "Show on"))
                        Spacer()
                        Text(displayName(settings.screenSelection)).foregroundStyle(.secondary)
                    }
                    ChoiceCards(
                        selection: $settings.screenSelection, options: [.all, .main, .builtIn, .external],
                        label: displayName
                    ) { selection, selected in
                        DisplayThumbnail(selection: selection, selected: selected)
                    }
                }
            }

            Section(tr("Размер и положение", "Size and position")) {
                LabeledContent {
                    Picker(tr("Остров на мониторе", "Island on a monitor"), selection: $settings.monitorPlacement) {
                        Text(tr("Поверх строки меню", "Over the menu bar")).tag(MonitorPlacement.overMenuBar)
                        Text(tr("Под ней", "Below it")).tag(MonitorPlacement.belowMenuBar)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    RowLabel(
                        title: tr("Остров на мониторе", "Island on a monitor"),
                        subtitle: tr("На MacBook с вырезом остров всегда под строкой меню.", "On a MacBook with a notch the island is always below the menu bar."))
                }
                SliderRow(
                    title: tr("Смещение вниз", "Move down"), value: $settings.verticalOffset,
                    range: AppSettings.Limits.verticalOffset, step: 1, format: SettingsFormat.points)
                SliderRow(
                    title: tr("Размер чёлки", "Notch size"), value: $settings.notchScale,
                    range: AppSettings.Limits.scale, step: 0.05, format: SettingsFormat.percent)
                SliderRow(
                    title: tr("Размер острова", "Island size"), value: $settings.islandScale,
                    range: AppSettings.Limits.scale, step: 0.05, format: SettingsFormat.percent)
            }
        }
        .formStyle(.grouped)
    }

    private func lookName(_ style: IslandStylePreference) -> String {
        switch style {
        case .automatic: tr("Авто", "Auto")
        case .island: tr("Остров", "Island")
        case .notch: tr("Чёлка", "Notch")
        }
    }

    private func displayName(_ selection: ScreenSelection) -> String {
        switch selection {
        case .all: tr("Все экраны", "All displays")
        case .main: tr("Основной", "Primary")
        case .builtIn: tr("Встроенный", "Built-in")
        case .external: tr("Внешние", "External")
        }
    }

    private var styleNote: String {
        switch settings.islandStyle {
        case .automatic:
            tr("Чёлка на MacBook с вырезом, отдельный остров на остальных экранах.", "The notch on a MacBook with a notch, a separate island on other screens.")
        case .island:
            tr("Отдельная капсула на всех экранах. На MacBook с вырезом она под строкой меню.", "A separate pill on every screen. On a MacBook with a notch it sits below the menu bar.")
        case .notch:
            tr("«Чёлка» на всех экранах. Где выреза нет, она нарисована сверху по центру.", "The notch look on every screen. Where there is no notch it is drawn at the top centre.")
        }
    }
}

// MARK: - Now Playing

struct NowPlayingPage: View {
    @Bindable var settings: AppSettings
    let media: NowPlayingModel
    @State private var audio = AudioStatusModel.shared

    var body: some View {
        Form {
            Section {
                IslandPreview(settings: settings, media: media, expanded: true)
            }

            Section(tr("Раскрытие", "Expanding")) {
                ToggleRow(
                    symbol: "cursorarrow.rays", color: .blue, title: tr("Раскрывать при наведении", "Expand on hover"),
                    subtitle: tr("Иначе — щелчком по острову.", "Otherwise click the island."),
                    isOn: $settings.expandOnHover)
                if settings.expandOnHover {
                    SliderRow(
                        title: tr("Задержка перед раскрытием", "Delay before expanding"),
                        subtitle: tr("Курсор, проходящий мимо к строке меню, не раскроет остров.", "A pointer passing by on its way to the menu bar does not open it."),
                        value: $settings.hoverDelay, range: AppSettings.Limits.hoverDelay, step: 0.1,
                        format: SettingsFormat.seconds)
                }
                SliderRow(
                    title: tr("Задержка сворачивания", "Delay before collapsing"),
                    subtitle: tr("Сколько остров остаётся раскрытым, когда курсор ушёл.", "How long the island stays open after the pointer leaves."),
                    value: $settings.collapseDelay, range: AppSettings.Limits.collapseDelay, step: 0.1,
                    format: SettingsFormat.seconds)
            }

            Section(tr("Новый трек", "New track")) {
                ToggleRow(
                    symbol: "music.note.list", color: .pink, title: tr("Раскрывать при смене трека", "Expand when the track changes"),
                    subtitle: tr("Остров ненадолго показывает обложку и название нового трека.", "The island briefly shows the new track's artwork and title."),
                    isOn: $settings.expandOnTrackChange)
                if settings.expandOnTrackChange {
                    SliderRow(
                        title: tr("Держать раскрытым", "Keep open for"), value: $settings.trackChangeSeconds,
                        range: AppSettings.Limits.trackChangeSeconds, step: 0.5, format: SettingsFormat.seconds)
                }
            }

            Section(tr("Пауза", "Paused")) {
                ToggleRow(
                    symbol: "pause.fill", color: .orange, title: tr("Прятать на паузе", "Hide when paused"),
                    subtitle: tr("Выключите, чтобы остров на паузе оставался на экране.", "Turn off to keep a paused island on screen."),
                    isOn: $settings.autoHideEnabled)
                if settings.autoHideEnabled {
                    SliderRow(
                        title: tr("Спрятать через", "Hide after"), value: $settings.autoHideSeconds,
                        range: AppSettings.Limits.autoHideSeconds, step: 5, format: SettingsFormat.duration)
                }
            }

            Section(tr("Свёрнутый остров", "Compact island")) {
                ToggleRow(
                    symbol: "textformat", color: .gray, title: tr("Название трека", "Track title"),
                    subtitle: tr("Между обложкой и полосками; длинное прокручивается.", "Between the artwork and the bars; a long one scrolls."),
                    isOn: $settings.compactTitle)
                ToggleRow(
                    symbol: "paintpalette.fill", color: .purple, title: tr("Цвет по обложке", "Colour from artwork"),
                    subtitle: tr("Полоски и название окрашиваются в цвет обложки.", "The bars and the title take the artwork's colour."),
                    isOn: $settings.tintFromArtwork)
                LabeledContent {
                    Picker(tr("Эквалайзер", "Equaliser"), selection: $settings.liveEqualizer) {
                        Text(tr("Анимация", "Animation")).tag(false)
                        Text(tr("По звуку", "Live sound")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    RowLabel(symbol: "waveform", color: .red, title: tr("Эквалайзер", "Equaliser"), subtitle: audioNote)
                }
                if settings.liveEqualizer && audio.status == .silent {
                    Button(tr("Открыть настройки конфиденциальности…", "Open Privacy settings…")) {
                        // Privacy & Security → Screen & System Audio Recording.
                        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var audioNote: String {
        guard settings.liveEqualizer else {
            return tr("Полоски просто анимируются.", "The bars just animate.")
        }
        switch audio.status {
        case .live: return tr("Слушает звук Mac: только уровни, звук не меняется.", "Listening to the Mac's sound: levels only, the sound is not changed.")
        case .silent: return tr("Звука нет. Если музыка играет, включите Islet в «Конфиденциальность и безопасность» → «Запись экрана и системного звука» → «Только запись системного звука», затем перезапустите Islet.", "No sound. If music is playing, turn Islet on in Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, then restart Islet.")
        case .failed(let why): return tr("Не удалось подключиться к звуку: ", "Could not attach to audio: ") + why
        case .off, .starting: return tr("macOS один раз спросит разрешение на запись системного звука.", "macOS asks once for System Audio Recording permission.")
        }
    }
}

// MARK: - Timer

struct TimerPage: View {
    @Bindable var settings: AppSettings
    let activities: ActivityModel

    private static let minutes = [1, 5, 10, 15, 25, 30]

    var body: some View {
        Form {
            Section(tr("Запустить", "Start")) {
                RowLabel(
                    symbol: "timer", color: .orange, title: tr("Таймер", "Timer"),
                    subtitle: tr("Капсула с кольцом рядом с островом; щелчок раскрывает её. То же есть в меню в строке меню.", "A capsule with a ring beside the island; click it to open. Also in the menu bar menu."))
                HStack(spacing: 8) {
                    ForEach(Self.minutes, id: \.self) { value in
                        Button(tr("\(value) мин", "\(value) min")) { activities.startTimer(minutes: Double(value)) }
                    }
                }
                .controlSize(.small)
                LabeledContent {
                    Button(tr("Запустить", "Start")) { activities.startStopwatch() }
                        .controlSize(.small)
                } label: {
                    RowLabel(
                        symbol: "stopwatch", color: .orange, title: tr("Секундомер", "Stopwatch"),
                        subtitle: tr("Циферблат со стрелкой рядом с островом.", "A dial with a hand beside the island."))
                }
            }

            Section(tr("Звук", "Sound")) {
                ToggleRow(
                    symbol: "bell.fill", color: .red, title: tr("Звук по окончании", "Sound when it ends"),
                    subtitle: tr("Кроме звука, капсула 10 секунд показывает «Готово».", "Besides the sound, the capsule shows Done for 10 seconds."),
                    isOn: $settings.timerSound)
                if settings.timerSound {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Picker(tr("Звук", "Sound"), selection: $settings.timerSoundName) {
                                ForEach(AppSettings.timerSounds, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            Button {
                                AppModel.playTimerSound(settings.timerSoundName)
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .help(tr("Прослушать", "Play"))
                            .accessibilityLabel(tr("Прослушать", "Play"))
                        }
                    } label: {
                        RowLabel(symbol: "speaker.wave.2.fill", color: .pink, title: tr("Звук сигнала", "Alert sound"))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Battery

struct BatteryPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ToggleRow(
                    symbol: "battery.75percent", color: .green, title: tr("Уведомления о питании", "Power notices"),
                    subtitle: tr("Остров ненадолго растягивается и показывает заряд. Читается только состояние батареи, без разрешений. На Mac без батареи их не бывает.", "The island stretches for a moment and shows the charge. Only the battery state is read, no permissions. A Mac without a battery never shows them."),
                    isOn: $settings.showPowerActivity)
            }
            if settings.showPowerActivity {
                Section(tr("Когда показывать", "When to show")) {
                    ToggleRow(
                        symbol: "bolt.fill", color: .green, title: tr("Зарядка подключена или отключена", "Charger plugged in or out"),
                        isOn: $settings.showChargerNotices)
                    ToggleRow(
                        symbol: "battery.25percent", color: .red, title: tr("Низкий заряд", "Low battery"),
                        subtitle: tr("Один раз, когда заряд опускается до порога.", "Once, when the charge drops to the threshold."),
                        isOn: $settings.showLowBatteryNotice)
                    if settings.showLowBatteryNotice {
                        LabeledContent {
                            Picker(tr("Порог", "Threshold"), selection: $settings.lowBatteryThreshold) {
                                ForEach(PowerMonitor.lowThresholdChoices, id: \.self) { Text("\($0) %").tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        } label: {
                            RowLabel(title: tr("Порог низкого заряда", "Low battery at"))
                        }
                    }
                }
                Section(tr("Показ", "Display")) {
                    NoticeDurationRow(settings: settings)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Headphones

struct HeadphonesPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ToggleRow(
                    symbol: "airpodspro", color: .blue, title: tr("Подключение наушников", "Headphones connected"),
                    subtitle: tr("Когда Bluetooth-наушники или колонка становятся выходом звука, остров показывает устройство и его название.", "When Bluetooth headphones or a speaker become the sound output, the island shows the device and its name."),
                    isOn: $settings.showHeadphonesActivity)
            }
            if settings.showHeadphonesActivity {
                Section(tr("Показ", "Display")) {
                    NoticeDurationRow(settings: settings)
                }
            }
            Section {
                RowLabel(
                    symbol: "battery.50percent", color: .gray, title: tr("Заряд наушников", "Headphone battery"),
                    subtitle: tr("Не показывается: для этого нужно разрешение Bluetooth или закрытый API Apple.", "Not shown: it would need Bluetooth permission or a private Apple API."))
            }
        }
        .formStyle(.grouped)
    }
}

/// How long the power and headphones notices stay; one setting for both.
struct NoticeDurationRow: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SliderRow(
            title: tr("Длительность уведомления", "Notice length"),
            subtitle: tr("Общая для батареи и наушников.", "Shared by battery and headphones."),
            value: $settings.noticeSeconds, range: AppSettings.Limits.noticeSeconds, step: 1,
            format: SettingsFormat.seconds)
    }
}

// MARK: - Downloads

struct TransfersPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ToggleRow(
                    symbol: "arrow.down.circle.fill", color: .purple, title: tr("Копирование и загрузка файлов", "File copies and downloads"),
                    subtitle: tr("Капсула с процентом рядом с островом.", "A capsule with the percent beside the island."),
                    isOn: $settings.showTransferActivity)
            }
            Section(tr("Что читается", "What is read")) {
                RowLabel(
                    symbol: "folder.fill", color: .purple, title: tr("Только процент", "Percent only"),
                    subtitle: tr("Следит за «Загрузками», «Рабочим столом», «Документами» и подключёнными томами. Имена и содержимое файлов не читаются. Экспериментально.", "Watches Downloads, Desktop, Documents and mounted volumes. File names and contents are never read. Experimental."))
            }
        }
        .formStyle(.grouped)
    }
}
