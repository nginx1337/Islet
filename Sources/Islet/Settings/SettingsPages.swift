import AppKit
import IsletCore
import SwiftUI

// The pages of the settings window, in the manner of System Settings: a header with the page's icon
// (or a live preview of the island), grouped sections of plain rows with a grey line of explanation,
// notes under the sections, and Restore Defaults at the bottom.

/// A grey note under a section.
private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralPage: View {
    @Bindable var settings: AppSettings
    @State private var loginItem = LoginItem.isEnabled
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section { PageHeader(page: .general) }

            Section {
                ToggleRow(
                    title: tr("Открывать при входе", "Open at login"),
                    subtitle: tr("Islet запустится сам, когда вы войдёте в систему.", "Islet starts by itself when you log in."),
                    isOn: $loginItem)
                    .onChange(of: loginItem) { _, enabled in
                        guard enabled != (LoginItem.isEnabled || LoginItem.needsApproval) else { return }
                        loginMessage = LoginItem.set(enabled)
                        loginItem = LoginItem.isEnabled || LoginItem.needsApproval
                    }
                if let loginMessage {
                    Footnote(loginMessage)
                }
                ToggleRow(
                    title: tr("Значок в строке меню", "Menu bar icon"),
                    subtitle: tr(
                        "Меню с плеером, таймером и настройками. Без значка настройки открываются, если запустить Islet ещё раз.",
                        "A menu with the player, the timer and the settings. Without it, open Islet again to get the settings."),
                    isOn: $settings.showMenuBarIcon)
                LabeledContent {
                    HotKeyField(combo: $settings.hotKey)
                } label: {
                    RowLabel(
                        title: tr("Сочетание клавиш", "Shortcut"),
                        subtitle: tr("Раскрывает и сворачивает остров, возвращает спрятанный.", "Expands and collapses the island, brings a hidden one back."))
                }
                Picker(tr("Язык", "Language"), selection: $settings.language) {
                    Text(tr("Как в системе", "System")).tag(AppLanguage.system)
                    Text("Русский").tag(AppLanguage.ru)
                    Text("English").tag(AppLanguage.en)
                }
            }

            Section {
                ChoiceCards(selection: $settings.appTheme, options: AppTheme.allCases, label: themeName) { theme, _ in
                    ThemeThumbnail(theme: theme)
                }
            } header: {
                Text(tr("Оформление", "Appearance"))
            } footer: {
                Footnote(tr("Окна и меню Islet. Сам остров всегда чёрный.", "Islet's windows and menus. The island itself is always black."))
            }

            Section {
                LabeledContent(tr("Спрятать", "Hide"), value: tr("Щелчок колёсиком по острову", "Wheel click on the island"))
                LabeledContent(tr("Вернуть", "Bring back"), value: tr("Колёсиком там же или сочетанием клавиш", "Wheel click there, or the shortcut"))
            } header: {
                Text(tr("Спрятать остров", "Hiding the island"))
            } footer: {
                Footnote(tr("Остров прячется вместе с капсулой активности. Вернуть его можно и из меню в строке меню.", "The island hides with its activity capsule. It can also be brought back from the menu bar menu."))
            }

            Section {} footer: { RestoreDefaultsButton(page: .general, settings: settings) }
        }
        .formStyle(.grouped)
        .onAppear { loginItem = LoginItem.isEnabled || LoginItem.needsApproval }
    }

    private func themeName(_ theme: AppTheme) -> String {
        switch theme {
        case .system: tr("Авто", "Auto")
        case .light: tr("Светлое", "Light")
        case .dark: tr("Тёмное", "Dark")
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
            Section { PageHeader(page: .permissions) }

            Section(tr("Используется", "In use")) {
                LabeledContent {
                    HStack(spacing: 10) {
                        StatusBadge(text: sourceState, color: sourceColor)
                        if case .primary = media.sourceStatus {} else {
                            Button(tr("Повторить", "Retry")) { media.retryPrimarySource() }
                        }
                    }
                } label: {
                    RowLabel(symbol: "music.note", color: .pink, title: tr("Что играет", "Now playing"), subtitle: sourceNote)
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
                            "Только для полосок эквалайзера: считаются уровни четырёх полос частот, звук не записывается и не сохраняется. Можно отказать — полоски просто анимируются.",
                            "Only for the equaliser bars: the levels of four frequency bands; nothing is recorded or stored. You can refuse; the bars then just animate."))
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
                    symbol: "folder.fill", color: .cyan, title: tr("Файлы", "Files"),
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
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("Islet").font(.largeTitle.weight(.bold))
                    Text(tr("Версия ", "Version ") + version).foregroundStyle(.secondary)
                    Text(tr("«Сейчас играет» в виде острова у верхнего края экрана.", "Now Playing as an island at the top of the screen."))
                        .font(.callout)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            Section {
                Text(tr(
                    "Islet не собирает статистику и не ходит в сеть. Исключение — обложки Spotify в запасном режиме. Подробнее — в разделе «Разрешения».",
                    "Islet collects nothing and stays offline, except Spotify artwork in fallback mode. See Permissions for details."))
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(tr("Конфиденциальность", "Privacy"))
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
            } footer: {
                Footnote(tr("Наведите курсор на остров, чтобы он раскрылся.", "Point at the island to open it."))
            }

            Section {
                ChoiceCards(
                    selection: $settings.islandStyle, options: [.automatic, .island, .notch], label: lookName
                ) { style, _ in
                    LookThumbnail(style: style)
                }
            } header: {
                Text(tr("Вид", "Look"))
            } footer: {
                Footnote(styleNote)
            }

            Section {
                ToggleRow(
                    title: tr("Тонкая обводка", "Thin outline"),
                    subtitle: tr("Едва заметный светлый край, как у iPhone на тёмных обоях.", "A faint light edge, as on the iPhone over a dark wallpaper."),
                    isOn: $settings.islandOutline)
                ToggleRow(
                    title: tr("В полноэкранных приложениях", "In full-screen apps"),
                    subtitle: tr("Показывать остров и поверх программ на весь экран.", "Show the island over full-screen apps too."),
                    isOn: $settings.showInFullScreen)
            }

            Section {
                ChoiceCards(
                    selection: $settings.screenSelection, options: [.all, .main, .builtIn, .external],
                    label: displayName
                ) { selection, selected in
                    DisplayThumbnail(selection: selection, selected: selected)
                }
            } header: {
                Text(tr("Дисплеи", "Displays"))
            }

            Section(tr("Размер и положение", "Size and position")) {
                Picker(selection: $settings.monitorPlacement) {
                    Text(tr("Поверх строки меню", "Over the menu bar")).tag(MonitorPlacement.overMenuBar)
                    Text(tr("Под ней", "Below it")).tag(MonitorPlacement.belowMenuBar)
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

            Section {} footer: { RestoreDefaultsButton(page: .island, settings: settings) }
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
        case .all: tr("Все", "All")
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
                    title: tr("Раскрывать при наведении", "Expand on hover"),
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
                    title: tr("Показывать новый трек", "Show a new track"),
                    subtitle: tr("Остров ненадолго раскрывается с обложкой и названием.", "The island opens for a moment with the artwork and the title."),
                    isOn: $settings.expandOnTrackChange)
                if settings.expandOnTrackChange {
                    SliderRow(
                        title: tr("Держать раскрытым", "Keep open for"), value: $settings.trackChangeSeconds,
                        range: AppSettings.Limits.trackChangeSeconds, step: 0.5, format: SettingsFormat.seconds)
                }
            }

            Section(tr("Пауза", "Paused")) {
                ToggleRow(
                    title: tr("Прятать на паузе", "Hide when paused"),
                    subtitle: tr("Выключите, чтобы остров на паузе оставался на экране.", "Turn off to keep a paused island on screen."),
                    isOn: $settings.autoHideEnabled)
                if settings.autoHideEnabled {
                    SliderRow(
                        title: tr("Спрятать через", "Hide after"), value: $settings.autoHideSeconds,
                        range: AppSettings.Limits.autoHideSeconds, step: 5, format: SettingsFormat.duration)
                }
            }

            Section {
                ToggleRow(
                    title: tr("Название трека", "Track title"),
                    subtitle: tr("Между обложкой и полосками; длинное прокручивается.", "Between the artwork and the bars; a long one scrolls."),
                    isOn: $settings.compactTitle)
                ToggleRow(
                    title: tr("Цвет по обложке", "Colour from artwork"),
                    subtitle: tr("Полоски и название окрашиваются в цвет обложки.", "The bars and the title take the artwork's colour."),
                    isOn: $settings.tintFromArtwork)
                Picker(selection: $settings.liveEqualizer) {
                    Text(tr("Анимация", "Animation")).tag(false)
                    Text(tr("По звуку", "Live sound")).tag(true)
                } label: {
                    RowLabel(title: tr("Полоски эквалайзера", "Equaliser bars"), subtitle: audioNote)
                }
                if settings.liveEqualizer && audio.status == .silent {
                    Button(tr("Открыть настройки конфиденциальности…", "Open Privacy Settings…")) {
                        // Privacy & Security → Screen & System Audio Recording.
                        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text(tr("Свёрнутый остров", "Compact island"))
            }

            Section {} footer: { RestoreDefaultsButton(page: .nowPlaying, settings: settings) }
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
            Section { PageHeader(page: .timer) }

            Section {
                LabeledContent(tr("Таймер", "Timer")) {
                    HStack(spacing: 6) {
                        ForEach(Self.minutes, id: \.self) { value in
                            Button(tr("\(value) мин", "\(value) min")) { activities.startTimer(minutes: Double(value)) }
                        }
                    }
                }
                LabeledContent(tr("Секундомер", "Stopwatch")) {
                    Button(tr("Запустить", "Start")) { activities.startStopwatch() }
                }
            } header: {
                Text(tr("Запустить", "Start"))
            } footer: {
                Footnote(tr("Таймер и секундомер запускаются и из меню в строке меню.", "The timer and the stopwatch also start from the menu bar menu."))
            }

            Section(tr("Окончание", "When it ends")) {
                ToggleRow(
                    title: tr("Звуковой сигнал", "Alert sound"),
                    subtitle: tr("Кроме звука, капсула 10 секунд показывает «Готово».", "Besides the sound, the capsule shows Done for 10 seconds."),
                    isOn: $settings.timerSound)
                if settings.timerSound {
                    LabeledContent(tr("Звук", "Sound")) {
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
                    }
                }
            }

            Section {} footer: { RestoreDefaultsButton(page: .timer, settings: settings) }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Battery

struct BatteryPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section { PageHeader(page: .battery) }

            Section {
                ToggleRow(title: tr("Уведомления о питании", "Power notices"), isOn: $settings.showPowerActivity)
            } footer: {
                Footnote(tr("Читается только состояние батареи, без разрешений. На Mac без батареи уведомлений нет.", "Only the battery state is read, with no permission. A Mac without a battery shows none."))
            }

            if settings.showPowerActivity {
                Section(tr("Когда показывать", "When to show")) {
                    ToggleRow(title: tr("Зарядка подключена или отключена", "Charger plugged in or out"), isOn: $settings.showChargerNotices)
                    ToggleRow(
                        title: tr("Низкий заряд", "Low battery"),
                        subtitle: tr("Один раз, когда заряд опускается до порога.", "Once, when the charge drops to the threshold."),
                        isOn: $settings.showLowBatteryNotice)
                    if settings.showLowBatteryNotice {
                        Picker(tr("Порог низкого заряда", "Low battery at"), selection: $settings.lowBatteryThreshold) {
                            ForEach(PowerMonitor.lowThresholdChoices, id: \.self) { Text("\($0) %").tag($0) }
                        }
                    }
                }
                Section {
                    NoticeDurationRow(settings: settings)
                }
            }

            Section {} footer: { RestoreDefaultsButton(page: .battery, settings: settings) }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Headphones

struct HeadphonesPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section { PageHeader(page: .headphones) }

            Section {
                ToggleRow(
                    title: tr("Подключение наушников", "Headphones connected"),
                    subtitle: tr("Значок устройства слева, его название справа.", "The device's glyph on the left, its name on the right."),
                    isOn: $settings.showHeadphonesActivity)
            } footer: {
                Footnote(tr("Заряд наушников не показывается: для этого нужно разрешение Bluetooth или закрытый API Apple.", "The headphones' battery is not shown: that would need Bluetooth permission or a private Apple API."))
            }

            if settings.showHeadphonesActivity {
                Section {
                    NoticeDurationRow(settings: settings)
                }
            }

            Section {} footer: { RestoreDefaultsButton(page: .headphones, settings: settings) }
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
            Section { PageHeader(page: .transfers) }

            Section {
                ToggleRow(
                    title: tr("Копирование и загрузка файлов", "File copies and downloads"),
                    subtitle: tr("Экспериментально.", "Experimental."),
                    isOn: $settings.showTransferActivity)
            } footer: {
                Footnote(tr(
                    "Islet следит за «Загрузками», «Рабочим столом», «Документами» и подключёнными томами и видит только процент. Имена и содержимое файлов не читаются.",
                    "Islet watches Downloads, Desktop, Documents and mounted volumes and sees only the percent. File names and contents are never read."))
            }

            Section {} footer: { RestoreDefaultsButton(page: .transfers, settings: settings) }
        }
        .formStyle(.grouped)
    }
}
