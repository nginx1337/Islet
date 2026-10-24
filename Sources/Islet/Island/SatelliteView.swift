import IsletCore
import SwiftUI

/// A live activity, drawn like the Dynamic Island draws it (see ``SatelliteMode``):
/// - bubble: a circle beside the music island with only a ring or a glyph, so nothing gets cut off;
/// - capsule: that circle widened under the pointer, with the buttons and the value;
/// - island: the activity in the island's own shape when nothing else is shown, glyph left, value right;
/// - banner: a notice (charger, headphones) that widens the island for a few seconds, with room for text.
/// Tap pauses or resumes a timer or stopwatch and dismisses everything else.
struct SatelliteView: View {
    let activity: LiveActivity
    let activities: ActivityModel
    let mode: SatelliteMode
    /// The pointer is on this activity (this island's own, since each screen has one).
    let hovering: Bool
    let layout: IslandLayout
    let size: CGSize

    private var height: CGFloat { size.height }
    private var scale: CGFloat { layout.scale }
    /// Glyphs sit in a circle as tall as the shape, so they are concentric with its rounded end.
    private var slot: CGFloat { height }
    /// Round buttons with an even ring of black around them.
    private var button: CGFloat { max(16, height - 8) }
    private var glyphSize: CGFloat { height * 0.46 }
    private var valueSize: CGFloat { max(11, height * 0.47) }
    /// Island and banner take the island's place, so they take its shape too.
    private var notchShaped: Bool { layout.style == .notch && (mode == .island || mode == .banner) }
    /// Width of each side of a physical notch, where island and banner content goes.
    private var ear: CGFloat? {
        guard notchShaped, SatellitePlacement.hasPhysicalNotch(layout) else { return nil }
        return max(0, (size.width - layout.notchWidth) / 2)
    }

    var body: some View {
        ZStack {
            background
            content
                .id("\(activity.kind)-\(mode)")
                .transition(.opacity)
        }
        .animation(IslandMotion.swap, value: activity.kind)
        .animation(IslandMotion.swap, value: mode)
        .contentShape(Rectangle())
        .onTapGesture { activities.primaryAction() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Shape

    @ViewBuilder
    private var background: some View {
        let outline = Color.white.opacity(layout.outline ? IslandOutline.opacity : 0)
        if notchShaped {
            let flare = layout.compact.topFlare, radius = layout.compact.cornerRadius
            NotchShape(flare: flare, bottomRadius: radius)
                .fill(.black)
                .overlay {
                    NotchShape(flare: flare, bottomRadius: radius, closed: false)
                        .stroke(outline, lineWidth: IslandOutline.width)
                }
                .padding(.horizontal, -flare)
        } else {
            Capsule(style: .continuous)
                .fill(.black)
                .overlay { Capsule(style: .continuous).strokeBorder(outline, lineWidth: IslandOutline.width) }
                .shadow(color: .black.opacity(layout.style == .floating ? 0.3 : 0), radius: 10, y: 4)
        }
    }

    // MARK: Content by mode

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .bubble:
            minimal
        case .capsule:
            leadingAndValue
        case .island:
            if let ear {
                // Beside a physical notch: the glyph in the left ear, the value in the right one.
                HStack(spacing: 0) {
                    leading.frame(width: ear)
                    Spacer(minLength: 0)
                    trailing.frame(width: ear)
                }
            } else {
                leadingAndValue
            }
        case .banner:
            banner
        }
    }

    /// The glyph or buttons at the rounded end, the value at the other.
    private var leadingAndValue: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: 6 * scale)
            trailing.padding(.trailing, height * 0.4)
        }
    }

    /// Only the ring or the glyph, centred in the circle.
    @ViewBuilder
    private var minimal: some View {
        switch activity.content {
        case .countdown(let timer) where timer.isFinished:
            glyph("bell.fill", tint: .orange)
        case .countdown(let timer):
            CountdownRing(timer: timer, tint: .orange, lineWidth: 2.5 * scale)
                .frame(width: height * 0.56, height: height * 0.56)
        case .stopwatch:
            glyph("stopwatch.fill", tint: .orange)
        case .transfer(let info):
            ProgressRing(fraction: info.fraction, tint: .blue, lineWidth: 2.5 * scale)
                .frame(width: height * 0.56, height: height * 0.56)
        case .power(let info):
            glyph(powerSymbol(info), tint: powerTint(info))
        case .headphones:
            glyph("headphones", tint: .white)
        }
    }

    // MARK: Leading: glyph, ring or buttons

    @ViewBuilder
    private var leading: some View {
        switch activity.content {
        case .countdown(let timer):
            if timer.isFinished {
                glyph("bell.fill", tint: .orange)
            } else {
                withButtons(running: timer.isRunning) {
                    CountdownRing(timer: timer, tint: .orange, lineWidth: 2.5 * scale)
                        .frame(width: glyphSize, height: glyphSize)
                }
            }
        case .stopwatch(let watch):
            withButtons(running: watch.isRunning) {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: glyphSize * 0.95, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        case .power(let info):
            glyph(powerSymbol(info), tint: powerTint(info))
        case .headphones:
            glyph("headphones", tint: .white)
        case .transfer(let info):
            ProgressRing(fraction: info.fraction, tint: .blue, lineWidth: 2.5 * scale)
                .frame(width: glyphSize, height: glyphSize)
                .frame(width: slot, height: slot)
        }
    }

    private func glyph(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: glyphSize * 0.9, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: slot, height: slot)
    }

    /// The glyph in its slot; under the pointer it gives way to ✕ and pause/play.
    private func withButtons<Glyph: View>(running: Bool, @ViewBuilder glyph: () -> Glyph) -> some View {
        ZStack(alignment: .leading) {
            glyph()
                .frame(width: slot, height: slot)
                .opacity(hovering ? 0 : 1)
            HStack(spacing: 5 * scale) {
                SatelliteButton(symbol: "xmark", glyph: .white, fill: .white.opacity(0.22), size: button) {
                    activities.dismissCurrent()
                }
                SatelliteButton(symbol: running ? "pause.fill" : "play.fill", glyph: .black, fill: .orange, size: button) {
                    activities.primaryAction()
                }
            }
            .padding(.leading, (height - button) / 2)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .animation(IslandMotion.swap, value: hovering)
    }

    // MARK: Trailing: the value

    @ViewBuilder
    private var trailing: some View {
        switch activity.content {
        case .countdown(let timer):
            if timer.isFinished {
                value(tr("Готово", "Done"), tint: .orange)
            } else {
                ActivityClock(running: timer.isRunning, size: valueSize, tint: .orange) { date in
                    TimeFormat.clock(timer.remaining(at: date), roundingUp: true)
                }
            }
        case .stopwatch(let watch):
            ActivityClock(running: watch.isRunning, size: valueSize, tint: .orange) { date in
                TimeFormat.clock(watch.elapsed(at: date))
            }
        case .power(let info):
            value("\(info.percent)%", tint: powerTint(info))
        case .headphones:
            value(tr("Подключено", "Connected"), tint: .white.opacity(0.6), size: valueSize * 0.85)
        case .transfer(let info):
            value(info.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…", tint: .white)
        }
    }

    private func value(_ text: String, tint: Color, size: CGFloat? = nil) -> some View {
        Text(text)
            .font(.system(size: size ?? valueSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Banner

    /// Glyph and title on the left, the value on the right; beside a physical notch each side gets its own ear.
    @ViewBuilder
    private var banner: some View {
        let left = HStack(spacing: 7 * scale) {
            Image(systemName: bannerSymbol)
                .font(.system(size: glyphSize * 0.9, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(bannerTint)
            Text(bannerTitle)
                .font(.system(size: valueSize * 0.9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.tail)
        }
        if let ear {
            HStack(spacing: 0) {
                left
                    .padding(.leading, height * 0.45)
                    .frame(width: ear, alignment: .leading)
                Spacer(minLength: 0)
                trailing
                    .padding(.trailing, height * 0.45)
                    .frame(width: ear, alignment: .trailing)
            }
        } else {
            HStack(spacing: 8 * scale) {
                left
                Spacer(minLength: 8 * scale)
                trailing
            }
            .padding(.horizontal, height * 0.45)
        }
    }

    private var bannerSymbol: String {
        switch activity.content {
        case .power(let info): powerSymbol(info)
        case .headphones: "headphones"
        default: "circle"
        }
    }

    private var bannerTint: Color {
        switch activity.content {
        case .power(let info): powerTint(info)
        default: .white
        }
    }

    private var bannerTitle: String {
        switch activity.content {
        case .power(let info):
            switch info.event {
            case .pluggedIn: tr("Зарядка", "Charging")
            case .unplugged: tr("От батареи", "On battery")
            case .low: tr("Низкий заряд", "Low battery")
            }
        case .headphones(let name):
            name.isEmpty ? tr("Наушники", "Headphones") : name
        default:
            ""
        }
    }

    private func powerSymbol(_ info: PowerInfo) -> String {
        if info.event == .pluggedIn { return "bolt.fill" }
        switch info.percent {
        case 76...: return "battery.100percent"
        case 51...: return "battery.75percent"
        case 26...: return "battery.50percent"
        case 11...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func powerTint(_ info: PowerInfo) -> Color {
        switch info.event {
        case .pluggedIn: .green
        case .low: .red
        case .unplugged: .white
        }
    }

    private var accessibilityText: String {
        switch activity.content {
        case .countdown(let timer):
            timer.isFinished
                ? tr("Таймер закончился", "Timer finished")
                : tr("Таймер, осталось ", "Timer, remaining ") + TimeFormat.clock(timer.remaining(at: Date()), roundingUp: true)
        case .stopwatch(let watch):
            tr("Секундомер ", "Stopwatch ") + TimeFormat.clock(watch.elapsed(at: Date()))
        case .power(let info):
            switch info.event {
            case .pluggedIn: tr("Зарядка подключена, ", "Charger connected, ") + "\(info.percent)%"
            case .unplugged: tr("Зарядка отключена, ", "Charger disconnected, ") + "\(info.percent)%"
            case .low: tr("Низкий заряд, ", "Low battery, ") + "\(info.percent)%"
            }
        case .headphones(let name):
            tr("Подключены наушники ", "Headphones connected ") + name
        case .transfer(let info):
            tr("Копирование файлов", "File transfer") + (info.fraction.map { " \(Int(($0 * 100).rounded()))%" } ?? "")
        }
    }
}

/// A time that redraws four times a second, and only while it runs and is on screen (a paused one is drawn once).
private struct ActivityClock: View {
    let running: Bool
    let size: CGFloat
    let tint: Color
    let text: (Date) -> String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !running)) { context in
            Text(text(context.date))
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// The ring of the iPhone timer: full at the start, running out clockwise.
private struct CountdownRing: View {
    let timer: CountdownTimer
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !timer.isRunning)) { context in
            let left = timer.fractionLeft(at: context.date)
            ZStack {
                Circle().stroke(tint.opacity(0.28), lineWidth: lineWidth)
                Circle()
                    .trim(from: 1 - left, to: 1)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: left)
            }
            .padding(lineWidth / 2)
        }
    }
}

/// Round button like the ones on the iPhone: a filled circle with a dark or light glyph.
private struct SatelliteButton: View {
    let symbol: String
    let glyph: Color
    let fill: Color
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Circular progress; a short arc when the size is unknown.
private struct ProgressRing: View {
    let fraction: Double?
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.28), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.04, fraction ?? 0.25))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
        }
        .padding(lineWidth / 2)
    }
}
