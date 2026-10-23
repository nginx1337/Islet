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
                    strip(marquee: marquee, offset: offset)
                        .mask { edgeFade(scrolling: marquee.isScrolling, moving: moving) }
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

    /// Full in the middle, fading out towards the edges while the text overflows.
    @ViewBuilder
    private func edgeFade(scrolling: Bool, moving: Bool) -> some View {
        if scrolling {
            let edge = 0.1
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

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
    }
}
