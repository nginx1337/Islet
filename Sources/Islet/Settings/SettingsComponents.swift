import AppKit
import IsletCore
import SwiftUI

// Building blocks of the settings pages, after System Settings: coloured icons, rows with a grey
// explanation under the title, picture cards to choose from, and a live preview of the island.

/// A white glyph on a coloured rounded square.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}

/// The top of a page, as in System Settings: a large icon, the page's name and what it is for.
struct PageHeader: View {
    let page: SettingsPage

    var body: some View {
        VStack(spacing: 8) {
            SettingsIcon(symbol: page.symbol, color: page.color, size: 54)
            Text(page.title).font(.title2.weight(.bold))
            Text(page.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// "Restore Defaults…" at the bottom right of a page, as in System Settings; asks first.
struct RestoreDefaultsButton: View {
    let page: SettingsPage
    let settings: AppSettings
    @State private var confirm = false

    var body: some View {
        HStack {
            Spacer()
            Button(tr("Восстановить исходные…", "Restore Defaults…")) { confirm = true }
        }
        .confirmationDialog(
            tr("Вернуть исходные настройки раздела «\(page.title)»?", "Restore the default \(page.title) settings?"),
            isPresented: $confirm
        ) {
            Button(tr("Восстановить", "Restore"), role: .destructive) { page.reset(settings) }
        } message: {
            Text(tr("Остальные разделы не изменятся.", "Other pages stay as they are."))
        }
    }
}

/// An optional icon, a title and an optional grey line under it.
struct RowLabel: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            if let symbol { SettingsIcon(symbol: symbol, color: color) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A switch with an icon, a title and an explanation.
struct ToggleRow: View {
    var symbol: String?
    var color: Color = .gray
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            RowLabel(symbol: symbol, color: color, title: title, subtitle: subtitle)
        }
        .toggleStyle(.switch)
    }
}

/// A title with its value on the right and a full-width slider under it.
struct SliderRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Slider(value: $value, in: range, step: step) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue(format(value))
        }
        .padding(.vertical, 2)
    }
}

/// A coloured dot and a short state.
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

/// A row of picture cards to choose from, like the appearance picker in System Settings.
struct ChoiceCards<Value: Hashable, Picture: View>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @ViewBuilder let picture: (Value, Bool) -> Picture

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 6) {
                        picture(option, selected)
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        selected ? Color.accentColor : Color.primary.opacity(0.12),
                                        lineWidth: selected ? 2.5 : 1)
                            }
                        Text(label(option))
                            .font(.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pictures

/// The desktop the small pictures are drawn on.
enum Desktop {
    static let gradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.18, blue: 0.36), Color(red: 0.42, green: 0.2, blue: 0.4), Color(red: 0.75, green: 0.33, blue: 0.3)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A sliver of desktop with a menu bar and the island or the notch on it.
struct MiniScreen: View {
    let notch: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Desktop.gradient
            Rectangle().fill(.white.opacity(0.16)).frame(height: 8)
            if notch {
                NotchShape(flare: 3, bottomRadius: 4).fill(.black).frame(width: 42, height: 11)
            } else {
                Capsule()
                    .fill(.black)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                    .frame(width: 40, height: 11)
                    .padding(.top, 12)
            }
        }
    }
}

/// The look picker: the notch, the separate island, or each where it fits.
struct LookThumbnail: View {
    let style: IslandStylePreference

    var body: some View {
        switch style {
        case .automatic:
            HStack(spacing: 0) {
                MiniScreen(notch: true)
                Rectangle().fill(.black.opacity(0.5)).frame(width: 2)
                MiniScreen(notch: false)
            }
        case .island:
            MiniScreen(notch: false)
        case .notch:
            MiniScreen(notch: true)
        }
    }
}

/// A tiny window in the light or dark look.
struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let window = dark ? Color(white: 0.16) : Color(white: 0.98)
        let sidebar = dark ? Color(white: 0.23) : Color(white: 0.9)
        let ink = dark ? Color(white: 0.46) : Color(white: 0.72)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 3.5, height: 3.5) }
                }
                ForEach(0..<4, id: \.self) { _ in Capsule().fill(ink).frame(width: 12, height: 2) }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(width: 21)
            .frame(maxHeight: .infinity)
            .background(sidebar)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(ink).frame(width: 18, height: 2.5)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 14, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.5)).frame(height: 8)
                Spacer(minLength: 0)
            }
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(window)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// The theme picker: as the system, light or dark.
struct ThemeThumbnail: View {
    let theme: AppTheme

    var body: some View {
        ZStack {
            Desktop.gradient
            switch theme {
            case .system:
                MiniWindow(dark: false).frame(width: 52, height: 40).offset(x: -10, y: 2)
                MiniWindow(dark: true).frame(width: 52, height: 40).offset(x: 10, y: 9)
            case .light:
                MiniWindow(dark: false).frame(width: 64, height: 46).offset(y: 5)
            case .dark:
                MiniWindow(dark: true).frame(width: 64, height: 46).offset(y: 5)
            }
        }
    }
}

/// The display picker.
struct DisplayThumbnail: View {
    let selection: ScreenSelection
    let selected: Bool

    var body: some View {
        ZStack {
            Color.primary.opacity(0.05)
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
    }

    private var symbol: String {
        switch selection {
        case .all: "display.2"
        case .main: "menubar.rectangle"
        case .builtIn: "laptopcomputer"
        case .external: "display"
        }
    }
}

/// The menu bar behind the preview island: the Apple menu, a few menus and status items.
struct MenuBarStrip: View {
    let height: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "apple.logo").font(.system(size: 11, weight: .semibold))
            ForEach(Array([30, 26, 38, 28].enumerated()), id: \.offset) { item in
                Capsule().frame(width: CGFloat(item.element), height: 5)
            }
            Spacer()
            ForEach(Array([12, 12, 30].enumerated()), id: \.offset) { item in
                Capsule().frame(width: CGFloat(item.element), height: 5)
            }
        }
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 12)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.2))
    }
}

/// The island as it looks with the current settings, drawn by the island's own view over a strip of
/// desktop: what plays now, or a sample track when nothing does. It takes no clicks.
struct IslandPreview: View {
    let settings: AppSettings
    let media: NowPlayingModel
    let expanded: Bool

    /// Room the preview has in a settings row; a larger island is scaled down to it.
    private static let room: CGFloat = 500
    private static let macBook = ScreenDescriptor(
        id: "preview-notch", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), backingScale: 2,
        safeAreaTop: 32, auxiliaryLeftWidth: 662, auxiliaryRightWidth: 662, isBuiltIn: true, isMain: true)
    private static let monitor = ScreenDescriptor(
        id: "preview-monitor", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), backingScale: 2,
        isMain: true, statusBarThickness: 24, visibleTopInset: 30)

    var body: some View {
        // The island look draws a separate island; the others show the notch of a MacBook.
        let screen = settings.islandStyle == .island ? Self.monitor : Self.macBook
        let layout = IslandLayoutEngine.layout(for: screen, settings: settings.layoutSettings)
        let source = media.state == nil ? NowPlayingModel.sample : media
        let compact = layout.compact(fittingTitle: Self.titleWidth(source.state?.title, layout: layout))
        let shape = expanded ? layout.expanded : compact
        let presentation: IslandPresentation = expanded ? .expanded(.hover) : .compact(dimmed: false)
        let fit = min(1, Self.room / max(1, shape.frame.width + 2 * shape.topFlare + 40))
        // Overlays do not take part in the layout: the strip is as wide as the row whatever the
        // island's size, and the island hangs from its top edge as from the screen's.
        Desktop.gradient
            .overlay(alignment: .top) { MenuBarStrip(height: screen.menuBarHeight * fit) }
            .overlay(alignment: .top) {
                IslandBody(
                    layout: layout, presentation: presentation, shape: shape, compactFrame: compact.frame,
                    media: source, onClick: {})
                    .frame(width: shape.frame.width, height: shape.frame.height)
                    .padding(.top, shape.frame.minY)
                    .scaleEffect(fit, anchor: .top)
            }
            .frame(height: (shape.frame.maxY + (expanded ? 22 : 18)) * fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Предпросмотр острова", "Island preview"))
    }

    /// Width of the compact title, measured as the island measures it.
    private static func titleWidth(_ title: String?, layout: IslandLayout) -> CGFloat? {
        guard layout.compactTitle, let title, !title.isEmpty else { return nil }
        let font = NSFont.systemFont(ofSize: IslandViewModel.compactTitleFontSize(for: layout), weight: .semibold)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }
}

extension NowPlayingModel {
    /// A track for the settings preview when nothing plays. It stands still at one spot.
    static let sample: NowPlayingModel = {
        let state = NowPlayingState(
            bundleID: "com.apple.Music", title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming",
            duration: 243, elapsed: 81, timestamp: Date(), rate: 0, isPlaying: true)
        let model = NowPlayingModel(switcher: SourceSwitcher(
            primary: SampleSource(state: state), fallback: SampleSource(state: nil), clock: SystemClock()))
        model.start()
        return model
    }()
}

/// Labels of the numbers in the settings, in the interface language.
enum SettingsFormat {
    private static var locale: Locale { Locale(identifier: currentLanguage == .ru ? "ru_RU" : "en_US") }

    /// "0,4 с", "at once" for zero.
    static func seconds(_ value: Double) -> String {
        guard value > 0 else { return tr("сразу", "at once") }
        let number = value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return number + tr(" с", " s")
    }

    /// "45 с", "2 мин", "2 мин 30 с".
    static func duration(_ value: Double) -> String {
        let total = Int(value.rounded())
        let minutes = total / 60, seconds = total % 60
        if minutes == 0 { return tr("\(seconds) с", "\(seconds) s") }
        if seconds == 0 { return tr("\(minutes) мин", "\(minutes) min") }
        return tr("\(minutes) мин \(seconds) с", "\(minutes) min \(seconds) s")
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    static func points(_ value: Double) -> String { "\(Int(value.rounded())) pt" }
}
