import AppKit
import IsletCore
import SwiftUI

/// Six thin bars, bass on the left and highs on the right (``EqualizerBars`` spreads the four
/// analysed bands over them). With system audio access they follow the real sound
/// (``AudioLevelMonitor``); without it they bounce decoratively. Core Animation layers either way.
struct EqualizerView: View {
    var color: NSColor
    var active: Bool
    @Environment(\.staticEqualizer) private var staticBars

    var body: some View {
        if staticBars {
            // Offscreen renders cannot show Core Animation layers: draw a still frame instead.
            GeometryReader { geometry in
                let heights: [CGFloat] = active ? [0.45, 0.8, 1, 0.6, 0.85, 0.4] : EqualizerNSView.rest
                let width = EqualizerNSView.barWidth(for: geometry.size.width)
                HStack(spacing: EqualizerNSView.spacing(for: geometry.size.width)) {
                    ForEach(0..<EqualizerBars.count, id: \.self) { i in
                        Capsule().fill(Color(color))
                            .frame(width: width, height: geometry.size.height * heights[i])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            EqualizerLayerView(color: color, active: active)
        }
    }
}

extension EnvironmentValues {
    @Entry var staticEqualizer = false
}

struct EqualizerLayerView: NSViewRepresentable {
    var color: NSColor
    var active: Bool

    func makeNSView(context: Context) -> EqualizerNSView {
        EqualizerNSView()
    }

    func updateNSView(_ view: EqualizerNSView, context: Context) {
        view.update(color: color, active: active)
    }
}

final class EqualizerNSView: NSView {
    private let bars: [CALayer] = (0..<EqualizerBars.count).map { _ in CALayer() }
    private var active = false
    private var live = false
    private var color = NSColor.white
    /// Rest heights (fraction of full height) and periods, so the bars do not move in step.
    static let rest: [CGFloat] = [0.3, 0.5, 0.65, 0.4, 0.55, 0.3]
    private let rest = EqualizerNSView.rest
    private let periods: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.49, 0.44, 0.52]
    /// Gap between bars as a fraction of a bar's width (the iPhone's bars are about this airy).
    private static let gapRatio: CGFloat = 0.8

    static func barWidth(for width: CGFloat) -> CGFloat {
        let n = CGFloat(EqualizerBars.count)
        return max(1.5, width / (n + (n - 1) * gapRatio))
    }

    static func spacing(for width: CGFloat) -> CGFloat {
        let n = CGFloat(EqualizerBars.count)
        return max(0, (width - barWidth(for: width) * n) / (n - 1))
    }
    private static let minimum: CGFloat = 0.14

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        for bar in bars { layer?.addSublayer(bar) }
    }

    @MainActor required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            AudioLevelMonitor.shared.register(self)
        } else {
            AudioLevelMonitor.shared.unregister(self)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = Self.barWidth(for: bounds.width)
        let spacing = Self.spacing(for: bounds.width)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: width / 2 + CGFloat(i) * (width + spacing), y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
        restart()
    }

    func update(color: NSColor, active: Bool) {
        let colorChanged = color != self.color
        self.color = color
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        for bar in bars {
            bar.backgroundColor = color.cgColor
        }
        CATransaction.commit()
        if active != self.active || colorChanged {
            self.active = active
            restart()
        }
    }

    /// Live: heights come from the audio (``apply(levels:)``). Otherwise the decorative bounce.
    func setLive(_ live: Bool) {
        guard live != self.live else { return }
        self.live = live
        restart()
    }

    /// Real levels, 0…1 per band (bass first), spread over the bars. Each update glides for one frame,
    /// so it looks continuous.
    func apply(levels: [Float]) {
        guard live, active else { return }
        let levels = EqualizerBars.spread(levels, to: bars.count)
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0 / 30)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (i, bar) in bars.enumerated() where i < levels.count {
            let height = Self.minimum + (1 - Self.minimum) * CGFloat(levels[i])
            bar.transform = CATransform3DMakeScale(1, height, 1)
        }
        CATransaction.commit()
    }

    private func restart() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        for (i, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "bounce")
            bar.transform = CATransform3DMakeScale(1, active ? rest[i] : Self.minimum + 0.1, 1)
            guard active, !live else { continue }
            let bounce = CABasicAnimation(keyPath: "transform.scale.y")
            bounce.fromValue = 0.2 + rest[i] * 0.3
            bounce.toValue = 1.0
            bounce.duration = periods[i]
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bounce.beginTime = CACurrentMediaTime() - Double(i) * 0.13
            bar.add(bounce, forKey: "bounce")
        }
        CATransaction.commit()
    }
}
