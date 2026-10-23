import IsletCore
import SwiftUI

/// The second capsule next to the island: one live activity, like the small bubble of Dynamic Island.
/// Tap pauses or resumes a timer or stopwatch and dismisses everything else; hovering a timer
/// shows pause and cancel buttons.
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
                .shadow(color: .black.opacity(style == .floating ? 0.35 : 0), radius: 10, y: 4)
            content(scale: s)
                .padding(.horizontal, 10 * s)
        }
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
            HStack(spacing: 6 * s) {
                leading(symbol: timer.isFinished ? "bell.fill" : "timer", tint: .orange, scale: s, controls: !timer.isFinished,
                        running: timer.isRunning, ringing: timer.isFinished)
                ActivityClock(running: timer.isRunning, scale: s, tint: timer.isFinished ? .red : .orange) { date in
                    TimeFormat.clock(timer.remaining(at: date), roundingUp: true)
                }
            }
        case .stopwatch(let watch):
            HStack(spacing: 6 * s) {
                leading(symbol: "stopwatch.fill", tint: .yellow, scale: s, controls: true, running: watch.isRunning, ringing: false)
                ActivityClock(running: watch.isRunning, scale: s, tint: .yellow) { date in
                    TimeFormat.clock(watch.elapsed(at: date))
                }
            }
        case .power(let info):
            HStack(spacing: 6 * s) {
                Image(systemName: powerSymbol(info))
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundStyle(powerTint(info))
                Text("\(info.percent)%")
                    .font(.system(size: 13 * s, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        case .headphones(let name):
            HStack(spacing: 6 * s) {
                Image(systemName: "headphones")
                    .font(.system(size: 14 * s, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(name.isEmpty ? tr("Наушники", "Headphones") : name)
                    .font(.system(size: 11 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case .transfer(let info):
            HStack(spacing: 6 * s) {
                ProgressRing(fraction: info.fraction, tint: .cyan)
                    .frame(width: 16 * s, height: 16 * s)
                Text(info.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…")
                    .font(.system(size: 13 * s, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }

    /// The icon; under the pointer a timer or stopwatch shows its two buttons instead.
    @ViewBuilder
    private func leading(symbol: String, tint: Color, scale s: CGFloat, controls: Bool, running: Bool, ringing: Bool) -> some View {
        if controls && hovering {
            HStack(spacing: 2 * s) {
                SatelliteButton(symbol: running ? "pause.fill" : "play.fill", scale: s) { activities.primaryAction() }
                SatelliteButton(symbol: "xmark", scale: s) { activities.dismissCurrent() }
            }
        } else {
            Image(systemName: symbol)
                .font(.system(size: 14 * s, weight: .semibold))
                .foregroundStyle(tint)
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

private struct SatelliteButton: View {
    let symbol: String
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10 * scale, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18 * scale, height: 18 * scale)
                .background(Circle().fill(.white.opacity(0.16)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Circular progress; a spinning arc when the size is unknown.
private struct ProgressRing: View {
    let fraction: Double?
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction ?? 0.25)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
