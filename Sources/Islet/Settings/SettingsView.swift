import AppKit
import IsletCore
import SwiftUI

/// Settings window (SwiftUI in an AppKit window, since Islet has no Dock icon or main menu).
/// Laid out like System Settings: pages in a sidebar with search, each page with its own Reset.
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let media: NowPlayingModel
    private let activities: ActivityModel

    init(settings: AppSettings, media: NowPlayingModel, activities: ActivityModel) {
        self.settings = settings
        self.media = media
        self.activities = activities
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, media: media, activities: activities))
            // The page title, its subtitle and the Reset button go into the window's toolbar.
            host.sceneBridgingOptions = [.title, .toolbars]
            host.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 820, height: 640))
            if !window.setFrameUsingName("IsletSettings") { window.center() }
            window.setFrameAutosaveName("IsletSettings")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// A titled group of pages in the sidebar.
struct SettingsSection: Identifiable {
    let title: String
    let pages: [SettingsPage]
    var id: String { title }
}

/// One page of the settings window.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general, permissions, about
    case island, nowPlaying
    case timer, battery, headphones, transfers

    var id: String { rawValue }

    /// Sidebar sections, in order.
    static var sections: [SettingsSection] {
        [
            SettingsSection(title: tr("Приложение", "App"), pages: [.general, .permissions, .about]),
            SettingsSection(title: tr("Остров", "Island"), pages: [.island, .nowPlaying]),
            SettingsSection(title: tr("Активности", "Activities"), pages: [.timer, .battery, .headphones, .transfers])
        ]
    }

    var title: String {
        switch self {
        case .general: tr("Основные", "General")
        case .permissions: tr("Разрешения", "Permissions")
        case .about: tr("О приложении", "About")
        case .island: tr("Остров и чёлка", "Island and notch")
        case .nowPlaying: tr("Сейчас играет", "Now Playing")
        case .timer: tr("Таймер", "Timer")
        case .battery: tr("Батарея", "Battery")
        case .headphones: tr("Наушники", "Headphones")
        case .transfers: tr("Загрузки", "Downloads")
        }
    }

    var subtitle: String {
        switch self {
        case .general: tr("Автозапуск, значок в строке меню, сочетание клавиш, язык и тема.", "Login, menu bar icon, shortcut, language and theme.")
        case .permissions: tr("Что Islet использует и чего не трогает.", "What Islet uses and what it never touches.")
        case .about: tr("Версия, конфиденциальность и лицензии.", "Version, privacy and licenses.")
        case .island: tr("Вид, экраны, размер и положение острова.", "Look, displays, size and position of the island.")
        case .nowPlaying: tr("Как остров раскрывается, прячется и выглядит с музыкой.", "How the island opens, hides and looks with music.")
        case .timer: tr("Таймер и секундомер рядом с островом.", "Timer and stopwatch beside the island.")
        case .battery: tr("Уведомления о зарядке и низком заряде.", "Charger and low battery notices.")
        case .headphones: tr("Уведомление о подключении наушников.", "A notice when headphones connect.")
        case .transfers: tr("Прогресс копирования и загрузки файлов.", "File copy and download progress.")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info"
        case .island: "rectangle.topthird.inset.filled"
        case .nowPlaying: "music.note"
        case .timer: "timer"
        case .battery: "battery.75percent"
        case .headphones: "headphones"
        case .transfers: "arrow.down"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .permissions: .blue
        case .about: .gray
        case .island: .indigo
        case .nowPlaying: .pink
        case .timer: .orange
        case .battery: .green
        case .headphones: .blue
        case .transfers: .purple
        }
    }

    /// Extra words the sidebar search finds the page by, in both languages.
    private var keywords: String {
        switch self {
        case .general: "login autostart menu bar icon shortcut hotkey language theme dark light вход автозапуск значок строка меню сочетание клавиши язык тема тёмная светлая"
        case .permissions: "privacy audio recording network bluetooth files keyboard конфиденциальность звук запись сеть файлы клавиатура"
        case .about: "version license privacy версия лицензия"
        case .island: "notch island look outline display monitor screen size position offset fullscreen чёлка вырез остров вид обводка дисплей монитор экран размер положение смещение полноэкранный"
        case .nowPlaying: "music hover expand collapse track pause hide title colour artwork equaliser equalizer музыка наведение раскрытие сворачивание трек пауза прятать название цвет обложка эквалайзер"
        case .timer: "stopwatch sound alarm секундомер звук сигнал"
        case .battery: "power charger low battery зарядка питание низкий заряд"
        case .headphones: "airpods bluetooth speaker наушники колонка"
        case .transfers: "files copy download progress файлы копирование загрузка прогресс"
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [title, subtitle, keywords].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Puts this page's settings back to their defaults. Pages that only show information have none.
    var canReset: Bool { self != .permissions && self != .about }

    func reset(_ settings: AppSettings) {
        switch self {
        case .general: settings.resetGeneral()
        case .island: settings.resetIsland()
        case .nowPlaying: settings.resetNowPlaying()
        case .timer: settings.resetTimer()
        case .battery: settings.resetBattery()
        case .headphones: settings.resetHeadphones()
        case .transfers: settings.resetTransfers()
        case .permissions, .about: break
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let media: NowPlayingModel
    let activities: ActivityModel
    @State private var page: SettingsPage?
    @State private var query = ""
    @State private var confirmReset = false

    init(settings: AppSettings, media: NowPlayingModel, activities: ActivityModel, page: SettingsPage = .general) {
        self.settings = settings
        self.media = media
        self.activities = activities
        _page = State(initialValue: page)
    }

    var body: some View {
        let current = page ?? .general
        NavigationSplitView {
            List(selection: $page) {
                ForEach(SettingsPage.sections) { section in
                    let pages = section.pages.filter { $0.matches(query) }
                    if !pages.isEmpty {
                        Section(section.title) {
                            ForEach(pages) { item in
                                Label {
                                    Text(item.title)
                                } icon: {
                                    SettingsIcon(symbol: item.symbol, color: item.color, size: 20)
                                }
                                .tag(item)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: tr("Поиск", "Search"))
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 280)
        } detail: {
            detail(current)
                .navigationTitle(current.title)
                .navigationSubtitle(current.subtitle)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(tr("Сбросить", "Reset")) { confirmReset = true }
                            .disabled(!current.canReset)
                            .help(tr("Вернуть настройки этого раздела к исходным", "Put this page's settings back to their defaults"))
                    }
                }
                .confirmationDialog(
                    tr("Сбросить настройки раздела «\(current.title)»?", "Reset the \(current.title) settings?"),
                    isPresented: $confirmReset
                ) {
                    Button(tr("Сбросить", "Reset"), role: .destructive) { current.reset(settings) }
                } message: {
                    Text(tr("Остальные разделы не изменятся.", "Other pages stay as they are."))
                }
        }
        .frame(minWidth: 760, minHeight: 520)
        // A new language redraws every page and the sidebar.
        .id(settings.language)
    }

    @ViewBuilder
    private func detail(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralPage(settings: settings)
        case .permissions: PermissionsPage(settings: settings, media: media)
        case .about: AboutPage()
        case .island: IslandPage(settings: settings, media: media)
        case .nowPlaying: NowPlayingPage(settings: settings, media: media)
        case .timer: TimerPage(settings: settings, activities: activities)
        case .battery: BatteryPage(settings: settings)
        case .headphones: HeadphonesPage(settings: settings)
        case .transfers: TransfersPage(settings: settings)
        }
    }
}

/// Records a global shortcut: click, press keys with ⌘, ⌥ or ⌃; Esc cancels.
struct HotKeyField: View {
    @Binding var combo: HotKeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
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
                .accessibilityLabel(tr("Убрать сочетание", "Remove shortcut"))
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
