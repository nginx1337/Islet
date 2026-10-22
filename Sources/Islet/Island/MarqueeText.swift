import IsletCore
import SwiftUI

/// One line of text that scrolls when it does not fit. Static text costs nothing:
/// the timeline is paused unless the text overflows.
struct MarqueeText: View {
    let text: String
    let font: Font
    var color: Color = .white
    /// Scroll only while shown (and playing, for the compact title).
    var active = true
    /// Blur the text where it runs out at the edges, instead of only fading it.
    var edgeBlur = false

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        let marquee = Marquee(textWidth: textWidth, containerWidth: containerWidth, speed: 28, gap: 36)
        let running = marquee.isScrolling && active
        Text(text).font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
                    let offset = running ? marquee.offset(at: context.date.timeIntervalSince(start)) : 0
                    let moving = offset < 0
                    ZStack(alignment: .leading) {
                        strip(marquee: marquee, offset: offset)
                            .mask { sharpMask(scrolling: marquee.isScrolling, moving: moving) }
                        if edgeBlur && marquee.isScrolling {
                            strip(marquee: marquee, offset: offset)
                                .blur(radius: 2.2)
                                .mask { edgeMask(moving: moving) }
                        }
                    }
                    .frame(width: containerWidth, alignment: .leading)
                    .clipped()
                }
            }
            .onChange(of: text) { start = Date() }
            .onChange(of: active) { _, now in if now { start = Date() } }
            .accessibilityLabel(text)
    }

    private func strip(marquee: Marquee, offset: CGFloat) -> some View {
        HStack(spacing: marquee.gap) {
            label
            if marquee.isScrolling { label }
        }
        .offset(x: offset)
        .frame(width: containerWidth, alignment: .leading)
    }

    /// Sharp text: full in the middle, fading out towards the edges while the text overflows.
    @ViewBuilder
    private func sharpMask(scrolling: Bool, moving: Bool) -> some View {
        if scrolling {
            let edge = edgeBlur ? 0.14 : 0.06
            LinearGradient(
                stops: [.init(color: moving ? .clear : .black, location: 0),
                        .init(color: .black, location: moving ? edge : 0),
                        .init(color: .black, location: 1 - edge * 1.6),
                        .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing)
        } else {
            Rectangle()
        }
    }

    /// Blurred copy: shows only near the edges, where the sharp text fades, and dissolves at the very end.
    private func edgeMask(moving: Bool) -> some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0),
                    .init(color: moving ? .black.opacity(0.8) : .clear, location: 0.05),
                    .init(color: .clear, location: 0.16),
                    .init(color: .clear, location: 0.74),
                    .init(color: .black.opacity(0.85), location: 0.9),
                    .init(color: .clear, location: 1)],
            startPoint: .leading, endPoint: .trailing)
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }
}
