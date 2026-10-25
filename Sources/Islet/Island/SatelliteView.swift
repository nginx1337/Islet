import IsletCore
import SwiftUI

/// A live activity, drawn the way the Dynamic Island draws it (see ``SatelliteMode``):
/// - bubble: a circle beside the music island with only a ring or a glyph; it comes out of the
///   island's edge like a drop and goes back into it;
/// - island: the activity in the island's own shape when nothing else plays, glyph left, value right;
/// - expanded: clicked open into a card with the time and big buttons;
/// - notice: a card that drops out of the island for a few seconds (charger, headphones).
/// Click opens the card, a click on the card closes it; the buttons pause, resume and cancel.
struct SatelliteView: View {
    let activity: LiveActivity
    let activities: ActivityModel
    let mode: SatelliteMode
    let layout: IslandLayout
    /// The outline it is drawn with (frame in panel coordinates, corner radius, notch flare).
    let shape: ShapeSpec
    /// The music island's outline right now: the bubble comes out of its right edge.
    let main: ShapeSpec
    let onTap: () -> Void

    /// 0 while a bubble is still inside the island, 1 once it is in its place (see ``AnyTransition/emerge``).
    @Environment(\.satelliteEmergence) private var emergence
    @Environment(\.displayScale) private var displayScale

    private var size: CGSize { shape.frame.size }
    private var scale: CGFloat { layout.scale }
    /// Height of the compact island; the bubble and the island mode are this tall.
    private var compactHeight: CGFloat { layout.compact.frame.height }
    /// Glyphs sit in a circle as tall as the compact shape, so they are concentric with its rounded end.
    private var slot: CGFloat { compactHeight }
    private var glyphSize: CGFloat { compactHeight * 0.46 }
    private var valueSize: CGFloat { max(11, compactHeight * 0.47) }
    private var notchShaped: Bool { shape.topFlare > 0 }
    /// Width of each side of a physical notch, where the island mode puts its glyph and value.
    private var ear: CGFloat? {
        guard mode == .island, SatellitePlacement.hasPhysicalNotch(layout) else { return nil }
        return max(0, (size.width - layout.notchWidth) / 2)
    }
    /// Cards keep their content below the menu bar or the notch.
    private var cardInset: CGFloat { layout.contentTopInset }

    var body: some View {
        let p = min(max(emergence, 0), 1)
        // A bubble travels from inside the island's right end to its place.
        let travel = mode == .bubble ? size.width + SatellitePlacement.bubbleOffset(from: main) : 0
        let shift = -(1 - p) * travel
        // Everything fills the frame it is given, which the island view animates: the outline morphs
        // from bubble to card and back. The content keeps its final size, sits at the top of a card or
        // in the middle of a bubble, and is clipped by the morphing outline, so it never reflows or
        // spills while the shape changes (like the island's own content).
        ZStack {
            background
            Color.clear
                .overlay(alignment: mode == .expanded || mode == .notice ? .top : .center) {
                    ZStack {
                        content
                            .frame(width: size.width, height: size.height)
                            .id("\(activity.kind)-\(mode)")
                            .transition(.opacity.animation(IslandMotion.swap))
                    }
                    // The ring or glyph shows up once the bubble is mostly out.
                    .opacity(mode == .bubble ? Self.ease((p - 0.55) / 0.35) : 1)
                }
                .clipShape(contentClip)
        }
        .offset(x: shift)
        .mask(alignment: .topLeading) {
            // Only what is outside the island shows, so the bubble seems to grow out of its edge.
            Rectangle()
                .frame(width: 6000, height: size.height + 60)
                .offset(x: mode == .bubble ? -SatellitePlacement.bubbleOffset(from: main) : -3000, y: -30)
        }
        .overlay(alignment: .topLeading) { drop(progress: p, shift: shift) }
        .contentShape(contentClip)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    /// The outline without the notch flares: rounded all round, or square at the top in the notch look.
    private var contentClip: UnevenRoundedRectangle {
        let r = shape.cornerRadius
        let top: CGFloat = notchShaped ? 0 : r
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: top,
            style: .continuous)
    }

    // MARK: Pixel grid

    /// A diameter in whole, even device pixels, so a centred ring has crisp, equal edges.
    private func ringSize(_ points: CGFloat) -> CGFloat {
        let s = max(displayScale, 1)
        return max(2, (points * s / 2).rounded() * 2) / s
    }

    /// A line width in whole device pixels.
    private func line(_ points: CGFloat) -> CGFloat {
        let s = max(displayScale, 1)
        return max(1, (points * s).rounded()) / s
    }

    private static func ease(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    // MARK: Shape

    /// Both outlines are always there and cross-fade with the spring that moves the frame, and the
    /// corner radius animates too, so a bubble morphs into a card instead of popping.
    private var background: some View {
        let outline = Color.white.opacity(layout.outline ? IslandOutline.opacity : 0)
        let flare = layout.compact.topFlare
        let radius = shape.cornerRadius
        return ZStack {
            NotchShape(flare: flare, bottomRadius: radius)
                .fill(.black)
                .overlay {
                    NotchShape(flare: flare, bottomRadius: radius, closed: false)
                        .stroke(outline, lineWidth: IslandOutline.width)
                }
                .padding(.horizontal, -flare)
                .opacity(notchShaped ? 1 : 0)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.black)
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(outline, lineWidth: IslandOutline.width)
                }
                .shadow(color: .black.opacity(layout.style == .floating ? 0.3 : 0), radius: 10, y: 4)
                .opacity(notchShaped ? 0 : 1)
        }
        .animation(IslandMotion.satellite, value: notchShaped)
    }

    /// The liquid neck between the island and a bubble coming out of it (or going back in): both shapes
    /// are blurred and thresholded together, which fills the corners where they meet. Only a band from
    /// just inside the island's edge to the bubble's left edge is shown: it covers the seam between the
    /// two outlines from the first frame, and stops short of the island's equaliser bars.
    private func drop(progress p: CGFloat, shift: CGFloat) -> some View {
        let h = size.height
        let edge = -SatellitePlacement.bubbleOffset(from: main) // the island's right edge, in this view
        let left = edge - h * 1.5
        let margin = h * 0.5
        let width = size.width - left + 8
        let showing = mode == .bubble && p > 0.02 && p < 0.98
        // How far into the island the band reaches: past its outline, short of the bars.
        let cover = min(5, h * 0.17)
        let notchEnd = layout.style == .notch
        let radius = min(main.cornerRadius, h / 2)
        return Canvas { context, _ in
            guard showing else { return }
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: max(3, h * 0.17)))
            context.drawLayer { layer in
                let end = CGRect(x: 0, y: margin, width: edge - left, height: h)
                let endShape = UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 0,
                    bottomTrailingRadius: radius, topTrailingRadius: notchEnd ? 0 : radius)
                layer.fill(endShape.path(in: end), with: .color(.black))
                layer.fill(Path(ellipseIn: CGRect(x: shift - left, y: margin, width: h, height: h)), with: .color(.black))
            }
        }
        .frame(width: width, height: h + 2 * margin)
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: max(edge, shift) + 1 - (edge - cover), height: h + 2 * margin)
                .offset(x: edge - cover - left)
        }
        .offset(x: left, y: -margin)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Content by mode

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .bubble:
            minimal
        case .island:
            if let ear {
                // Beside a physical notch: the glyph in the left ear, the value in the right one.
                HStack(spacing: 0) {
                    leading.frame(width: ear)
                    Spacer(minLength: 0)
                    trailing.frame(width: ear)
                }
            } else {
                HStack(spacing: 0) {
                    leading
                    Spacer(minLength: 6 * scale)
                    trailing.padding(.trailing, compactHeight * 0.4)
                }
            }
        case .expanded:
            card
        case .notice:
            noticeCard
        }
    }

    // MARK: Bubble and island

    /// Only the ring or the glyph, centred in the circle.
    @ViewBuilder
    private var minimal: some View {
        switch activity.content {
        case .countdown(let timer) where timer.isFinished:
            glyph("bell.fill", tint: .orange)
        case .countdown(let timer):
            CountdownRing(timer: timer, tint: .orange, lineWidth: line(2.5 * scale))
                .frame(width: ringSize(compactHeight * 0.56), height: ringSize(compactHeight * 0.56))
        case .stopwatch(let watch):
            StopwatchDial(watch: watch, tint: .orange, lineWidth: line(2.5 * scale))
                .frame(width: ringSize(compactHeight * 0.56), height: ringSize(compactHeight * 0.56))
        case .transfer(let info):
            ProgressRing(fraction: info.fraction, tint: .blue, lineWidth: line(2.5 * scale))
                .frame(width: ringSize(compactHeight * 0.56), height: ringSize(compactHeight * 0.56))
        case .power(let info):
            glyph(powerSymbol(info), tint: powerTint(info))
        case .headphones(let name):
            glyph(DeviceGlyph.symbol(forDeviceName: name), tint: .white)
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch activity.content {
        case .countdown(let timer) where timer.isFinished:
            glyph("bell.fill", tint: .orange)
        case .countdown(let timer):
            CountdownRing(timer: timer, tint: .orange, lineWidth: line(2.5 * scale))
                .frame(width: ringSize(glyphSize), height: ringSize(glyphSize))
                .frame(width: slot, height: slot)
        case .stopwatch(let watch):
            StopwatchDial(watch: watch, tint: .orange, lineWidth: line(2.5 * scale))
                .frame(width: ringSize(glyphSize), height: ringSize(glyphSize))
                .frame(width: slot, height: slot)
        case .transfer(let info):
            ProgressRing(fraction: info.fraction, tint: .blue, lineWidth: line(2.5 * scale))
                .frame(width: ringSize(glyphSize), height: ringSize(glyphSize))
                .frame(width: slot, height: slot)
        case .power(let info):
            glyph(powerSymbol(info), tint: powerTint(info))
        case .headphones(let name):
            glyph(DeviceGlyph.symbol(forDeviceName: name), tint: .white)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity.content {
        case .countdown(let timer) where timer.isFinished:
            value(tr("Готово", "Done"), tint: .orange)
        case .countdown(let timer):
            ActivityClock(running: timer.isRunning, size: valueSize, tint: .orange) { date in
                TimeFormat.clock(timer.remaining(at: date), roundingUp: true)
            }
        case .stopwatch(let watch):
            ActivityClock(running: watch.isRunning, size: valueSize, tint: .orange) { date in
                TimeFormat.clock(watch.elapsed(at: date))
            }
        case .transfer(let info):
            value(percentText(info.fraction), tint: .white)
        case .power(let info):
            value("\(info.percent)%", tint: powerTint(info))
        case .headphones:
            value(tr("Подключено", "Connected"), tint: .white.opacity(0.6))
        }
    }

    /// A monochrome SF Symbol, centred in the round slot at the shape's end.
    private func glyph(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: glyphSize * 0.9, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: slot, height: slot)
    }

    private func value(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: valueSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Expanded card

    /// Ring or glyph, a label and the big time, and the buttons on the right, like the iPhone's timer.
    private var card: some View {
        let s = scale
        return HStack(spacing: 14 * s) {
            cardLeading
                .frame(width: ringSize(46 * s), height: ringSize(46 * s))
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(cardLabel)
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                cardValue
            }
            Spacer(minLength: 8 * s)
            cardButtons
        }
        .padding(.horizontal, 20 * s)
        .frame(width: size.width, height: max(0, size.height - cardInset))
        .padding(.top, cardInset)
    }

    @ViewBuilder
    private var cardLeading: some View {
        let s = scale
        switch activity.content {
        case .countdown(let timer) where timer.isFinished:
            bigGlyph("bell.fill", tint: .orange)
        case .countdown(let timer):
            CountdownRing(timer: timer, tint: .orange, lineWidth: line(4 * s))
        case .stopwatch(let watch):
            StopwatchDial(watch: watch, tint: .orange, lineWidth: line(4 * s))
        case .transfer(let info):
            ProgressRing(fraction: info.fraction, tint: .blue, lineWidth: line(4 * s))
        case .power(let info):
            bigGlyph(powerSymbol(info), tint: powerTint(info))
        case .headphones(let name):
            bigGlyph(DeviceGlyph.symbol(forDeviceName: name), tint: .white)
        }
    }

    private var cardLabel: String {
        switch activity.content {
        case .countdown: tr("Таймер", "Timer")
        case .stopwatch: tr("Секундомер", "Stopwatch")
        case .transfer(let info):
            switch info.operation {
            case .download: tr("Загрузка", "Downloading")
            case .copy: tr("Копирование", "Copying")
            case .other: tr("Файлы", "Files")
            }
        case .power, .headphones: ""
        }
    }

    @ViewBuilder
    private var cardValue: some View {
        let fontSize = 30 * scale
        switch activity.content {
        case .countdown(let timer) where timer.isFinished:
            bigValue(tr("Готово", "Done"), tint: .orange)
        case .countdown(let timer):
            ActivityClock(running: timer.isRunning, size: fontSize, tint: .orange) { date in
                TimeFormat.clock(timer.remaining(at: date), roundingUp: true)
            }
        case .stopwatch(let watch):
            ActivityClock(running: watch.isRunning, size: fontSize, tint: .orange) { date in
                TimeFormat.clock(watch.elapsed(at: date))
            }
        case .transfer(let info):
            bigValue(percentText(info.fraction), tint: .white)
        case .power(let info):
            bigValue("\(info.percent)%", tint: powerTint(info))
        case .headphones:
            bigValue(tr("Подключено", "Connected"), tint: .white)
        }
    }

    /// ✕ and pause/resume for a running timer or stopwatch; only ✕ for a finished timer.
    @ViewBuilder
    private var cardButtons: some View {
        let s = scale
        let running = runningState
        if running != nil || isFinishedTimer {
            HStack(spacing: 10 * s) {
                SatelliteButton(
                    symbol: "xmark", glyph: .white, fill: .white.opacity(0.22), size: 44 * s,
                    label: tr("Убрать", "Remove")
                ) {
                    activities.dismissCurrent()
                }
                if let running {
                    SatelliteButton(
                        symbol: running ? "pause.fill" : "play.fill", glyph: .black, fill: .orange, size: 44 * s,
                        label: running ? tr("Пауза", "Pause") : tr("Продолжить", "Resume")
                    ) {
                        activities.primaryAction()
                    }
                }
            }
        }
    }

    /// Whether the timer or stopwatch runs; nil for activities without a pause button.
    private var runningState: Bool? {
        switch activity.content {
        case .countdown(let timer) where !timer.isFinished: return timer.isRunning
        case .stopwatch(let watch): return watch.isRunning
        case .countdown, .transfer, .power, .headphones: return nil
        }
    }

    private var isFinishedTimer: Bool {
        if case .countdown(let timer) = activity.content { return timer.isFinished }
        return false
    }

    private func bigGlyph(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 26 * scale, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
    }

    private func bigValue(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 30 * scale, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: Notice card

    /// A large glyph, a title and a subtitle; the charge as a ring on the right.
    private var noticeCard: some View {
        let s = scale
        return HStack(spacing: 14 * s) {
            Image(systemName: noticeSymbol)
                .font(.system(size: 28 * s, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(noticeTint)
                .frame(width: 44 * s, height: 44 * s)
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(noticeTitle)
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                Text(noticeSubtitle)
                    .font(.system(size: 12.5 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8 * s)
            if let charge {
                PercentRing(percent: charge.percent, tint: charge.tint, lineWidth: 3.5 * s, fontSize: 11 * s)
                    .frame(width: 40 * s, height: 40 * s)
            }
        }
        .padding(.horizontal, 18 * s)
        .frame(width: size.width, height: max(0, size.height - cardInset))
        .padding(.top, cardInset)
    }

    private var noticeSymbol: String {
        switch activity.content {
        case .power(let info) where info.event == .pluggedIn: "battery.100percent.bolt"
        case .power(let info): powerSymbol(info)
        case .headphones(let name): DeviceGlyph.symbol(forDeviceName: name)
        case .countdown, .stopwatch, .transfer: "circle"
        }
    }

    private var noticeTint: Color {
        switch activity.content {
        case .power(let info): powerTint(info)
        case .countdown, .stopwatch, .transfer, .headphones: .white
        }
    }

    private var noticeTitle: String {
        switch activity.content {
        case .power(let info):
            switch info.event {
            case .pluggedIn: tr("Зарядка", "Charging")
            case .unplugged: tr("От батареи", "On battery")
            case .low: tr("Низкий заряд", "Low battery")
            }
        case .headphones(let name):
            name.isEmpty ? tr("Наушники", "Headphones") : name
        case .countdown, .stopwatch, .transfer:
            ""
        }
    }

    private var noticeSubtitle: String {
        switch activity.content {
        case .power(let info):
            switch info.event {
            case .pluggedIn: tr("Кабель подключён", "Charger connected")
            case .unplugged: tr("Кабель отключён", "Charger disconnected")
            case .low: tr("Подключите зарядку", "Connect a charger")
            }
        case .headphones:
            tr("Подключено", "Connected")
        case .countdown, .stopwatch, .transfer:
            ""
        }
    }

    /// The battery charge for the ring of a power notice.
    private var charge: (percent: Int, tint: Color)? {
        if case .power(let info) = activity.content { return (info.percent, powerTint(info)) }
        return nil
    }

    // MARK: Helpers

    private func percentText(_ fraction: Double?) -> String {
        fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…"
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

// MARK: - Coming out of the island

extension EnvironmentValues {
    /// How far a bubble has come out of the island: 0 still inside it, 1 in its place.
    @Entry var satelliteEmergence: CGFloat = 1
}

/// Animates ``EnvironmentValues/satelliteEmergence`` while the bubble comes out of the island or goes back.
nonisolated struct EmergenceModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    @MainActor
    func body(content: Content) -> some View {
        content.environment(\.satelliteEmergence, progress)
    }
}

extension AnyTransition {
    /// The bubble comes out of the island's edge like a drop, and goes back into it when it ends.
    static var emerge: AnyTransition {
        let drop = AnyTransition.modifier(active: EmergenceModifier(progress: 0), identity: EmergenceModifier(progress: 1))
        return .asymmetric(insertion: drop.animation(IslandMotion.emerge), removal: drop.animation(IslandMotion.absorb))
    }
}

// MARK: - Pieces

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

/// The stopwatch drawn as its dial: a ring and a hand going round once a minute. As round and as centred
/// as the timer's ring (the SF Symbol has a crown on top that pulls its circle below the centre).
private struct StopwatchDial: View {
    let watch: Stopwatch
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        // Ten updates a second while it runs and is on screen; the hand moves 0.6° per update.
        TimelineView(.animation(minimumInterval: 0.1, paused: !watch.isRunning)) { context in
            let seconds = watch.elapsed(at: context.date).truncatingRemainder(dividingBy: 60)
            ZStack {
                Circle().stroke(tint.opacity(0.28), lineWidth: lineWidth)
                DialHand(angle: .degrees(seconds * 6))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle()
                    .fill(tint)
                    .frame(width: lineWidth * 1.8, height: lineWidth * 1.8)
            }
            .padding(lineWidth / 2)
        }
    }
}

/// A hand from the centre, pointing at `angle` clockwise from twelve.
nonisolated struct DialHand: Shape {
    var angle: Angle

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) / 2 * 0.62
        let radians = angle.radians
        var path = Path()
        path.move(to: centre)
        path.addLine(to: CGPoint(x: centre.x + sin(radians) * length, y: centre.y - cos(radians) * length))
        return path
    }
}

/// Round button like the ones on the iPhone: a filled circle with a dark or light glyph.
private struct SatelliteButton: View {
    let symbol: String
    let glyph: Color
    let fill: Color
    let size: CGFloat
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(glyph)
                // A triangle's visual centre is right of its box's centre: nudge ▶ like Apple does.
                .offset(x: symbol == "play.fill" ? size * 0.035 : 0)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .help(label)
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

/// The battery charge as a ring with the number inside, like the Batteries widget.
private struct PercentRing: View {
    let percent: Int
    let tint: Color
    let lineWidth: CGFloat
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.28), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, Double(percent) / 100))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(lineWidth / 2)
    }
}
