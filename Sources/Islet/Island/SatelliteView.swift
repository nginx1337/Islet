import IsletCore
import SwiftUI

/// The second capsule next to the island: one live activity, like the small bubble of Dynamic Island.
/// An icon on the left, the value on the right. Tap pauses or resumes a timer or stopwatch and
/// dismisses everything else; under the pointer a timer widens and shows pause and cancel buttons.
struct SatelliteView: View {
    let activity: LiveActivity
    let activities: ActivityModel
    /// The pointer is on this capsule (this island's own, since each screen has one).
    let hovering: Bool
    let style: IslandStyle
    let scale: CGFloat

    var body: some View {
        let s = scale
        ZStack {
            Capsule(style: .continuous)
                .fill(.black)
                .shadow(color: .black.opacity(style == .floating ? 0.3 : 0), radius: 10, y: 4)
            content(scale: s)
                .id(activity.kind)
                .transition(.opacity)
                .padding(.horizontal, 11 * s)
        }
        .animation(IslandMotion.swap, value: activity.kind)
        .contentShape(Capsule())
        .onTapGesture { activities.primaryAction() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func content(scale s: CGFloat) -> some View {
        switch activity.content {
        case .countdown(let timer):
            HStack(spacing: 8 * s) {
                leading(symbol: timer.isFinished ? "bell.fill" : "timer", tint: .orange, scale: s,
                        controls: !timer.isFinished, running: timer.isRunning)
                Spacer(minLength: 0)
                if timer.isFinished {
                    value(tr("Готово", "Done"), tint: .orange, scale: s)
                } else {
                    ActivityClock(running: timer.isRunning, scale: s, tint: .orange) { date in
                        TimeFormat.clock(timer.remaining(at: date), roundingUp: true)
                    }
                }
            }
        case .stopwatch(let watch):
            HStack(spacing: 8 * s) {
                leading(symbol: "stopwatch.fill", tint: .orange, scale: s, controls: true, running: watch.isRunning)
                Spacer(minLength: 0)
                ActivityClock(running: watch.isRunning, scale: s, tint: .orange) { date in
                    TimeFormat.clock(watch.elapsed(at: date))
                }
            }
        case .power(let info):
            HStack(spacing: 8 * s) {
                glyph(powerSymbol(info), tint: powerTint(info), scale: s)
                Spacer(minLength: 0)
                value("\(info.percent)%", tint: powerTint(info), scale: s)
            }
        case .headphones(let name):
            HStack(spacing: 8 * s) {
                glyph("headphones", tint: .white, scale: s)
                Spacer(minLength: 0)
                Text(name.isEmpty ? tr("Наушники", "Headphones") : name)
                    .font(.system(size: 11.5 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case .transfer(let info):
            HStack(spacing: 8 * s) {
                ProgressRing(fraction: info.fraction, tint: .blue)
                    .frame(width: 16 * s, height: 16 * s)
                Spacer(minLength: 0)
                value(info.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…", tint: .white, scale: s)
            }
        }
    }

    private func glyph(_ symbol: String, tint: Color, scale s: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14 * s, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }

    private func value(_ text: String, tint: Color, scale s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 14 * s, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    /// The icon, and on top of it the two round buttons that fade in when the capsule widens.
    private func leading(symbol: String, tint: Color, scale s: CGFloat, controls: Bool, running: Bool) -> some View {
        let showButtons = controls && hovering
        return ZStack(alignment: .leading) {
            glyph(symbol, tint: tint, scale: s)
                .opacity(showButtons ? 0 : 1)
            if controls {
                HStack(spacing: 6 * s) {
                    SatelliteButton(symbol: "xmark", glyph: .white, fill: .white.opacity(0.22), scale: s) {
                        activities.dismissCurrent()
                    }
                    SatelliteButton(symbol: running ? "pause.fill" : "play.fill", glyph: .black, fill: tint, scale: s) {
                        activities.primaryAction()
                    }
                }
                .opacity(showButtons ? 1 : 0)
                .allowsHitTesting(showButtons)
            }
        }
        .animation(IslandMotion.swap, value: showButtons)
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
    let scale: CGFloat
    let tint: Color
    let text: (Date) -> String

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !running)) { context in
            Text(text(context.date))
                .font(.system(size: 14 * scale, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Round button like the ones on the iPhone: a filled circle with a dark or light glyph.
private struct SatelliteButton: View {
    let symbol: String
    let glyph: Color
    let fill: Color
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10 * scale, weight: .bold))
                .foregroundStyle(glyph)
                .frame(width: 22 * scale, height: 22 * scale)
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

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.04, fraction ?? 0.25))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
        }
    }
}
