import IsletCore
import SwiftUI

/// The island: one view for both styles. The style only changes the outline and the animations.
///
/// Both content layers are always laid out at their final size and revealed by the growing outline,
/// so nothing reflows while the island morphs. The artwork is a single view that glides between its
/// compact and expanded spots with the same spring as the outline.
struct IslandRootView: View {
    let model: IslandViewModel
    let media: NowPlayingModel

    var body: some View {
        let layout = model.layout
        let shape = model.shape
        ZStack(alignment: .topLeading) {
            IslandBody(layout: layout, presentation: model.presentation, shape: shape,
                       compactFrame: model.compactShape.frame, media: media) {
                model.onClick?()
            }
            .frame(width: shape.frame.width, height: shape.frame.height)
            .offset(x: shape.frame.minX, y: shape.frame.minY)
        }
        .frame(width: layout.panelFrame.width, height: layout.panelFrame.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) { satellite }
        .environment(\.colorScheme, .dark)
    }
}

extension IslandRootView {
    /// The second capsule beside the island: pops out of the island's edge and slides along with it.
    @ViewBuilder
    var satellite: some View {
        ZStack(alignment: .topLeading) {
            if let activity = model.activities.current, let frame = model.satelliteFrame {
                SatelliteView(activity: activity, activities: model.activities, hovering: model.satelliteHovering,
                              style: model.layout.style, scale: model.layout.scale)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(width: model.layout.panelFrame.width, height: model.layout.panelFrame.height, alignment: .topLeading)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.activities.current?.kind)
    }
}

/// Where things go inside the compact island.
struct CompactMetrics {
    let size: CGSize
    let art: CGFloat
    /// Width of the part of each ear that holds the artwork or the bars.
    let ear: CGFloat
    let artCenter: CGPoint
    let barsCenter: CGPoint
    let titleRect: CGRect?
    let titleFontSize: CGFloat

    init(layout: IslandLayout, frame: CGRect) {
        size = frame.size
        let h = frame.height
        art = max(14, min(h - 10, 24))
        switch layout.style {
        case .notch:
            let side = max(0, (frame.width - layout.notchWidth) / 2)
            ear = min(side, layout.compactEar)
            titleRect = layout.compactTitle && side - ear > 24
                ? CGRect(x: ear, y: 0, width: side - ear - 8, height: h) : nil
        case .floating:
            ear = layout.compactEar
            titleRect = layout.compactTitle ? CGRect(x: ear, y: 0, width: frame.width - 2 * ear, height: h) : nil
        }
        titleFontSize = IslandViewModel.compactTitleFontSize(for: layout)
        artCenter = CGPoint(x: ear / 2, y: h / 2)
        barsCenter = CGPoint(x: frame.width - ear / 2, y: h / 2)
    }
}

/// Where things go inside the expanded island.
struct ExpandedMetrics {
    let size: CGSize
    let s: CGFloat
    let inset: CGFloat
    var padding: CGFloat { 20 * s }
    var art: CGFloat { 56 * s }
    var spacing: CGFloat { 10 * s }
    let progressHeight: CGFloat = 14
    var block: CGFloat { art + spacing + progressHeight }
    var artCenter: CGPoint {
        let top = inset + max(0, (size.height - inset - block) / 2)
        return CGPoint(x: padding + art / 2, y: top + art / 2)
    }

    init(layout: IslandLayout) {
        size = layout.expanded.frame.size
        s = layout.scale
        inset = layout.contentTopInset
    }
}

struct IslandBody: View {
    let layout: IslandLayout
    let presentation: IslandPresentation
    let shape: ShapeSpec
    /// Compact frame fitted to the title (the layout's own compact frame is the widest case).
    let compactFrame: CGRect
    let media: NowPlayingModel
    let onClick: () -> Void

    var body: some View {
        let compact = CompactMetrics(layout: layout, frame: compactFrame)
        let expanded = ExpandedMetrics(layout: layout)
        let isExpanded = presentation.isExpanded
        let isCompact: Bool = if case .compact = presentation { true } else { false }
        let dimmed = presentation == .compact(dimmed: true)
        let accent = Color(media.accent.nsColor)
        let glowing = media.tintFromArtwork && presentation == .compact(dimmed: false) && media.artworkAccent != nil
        let width = shape.frame.width

        // Artwork: one view, two spots.
        let artSize = isExpanded ? expanded.art : compact.art
        let artCenter = isExpanded
            ? CGPoint(x: width / 2 - expanded.size.width / 2 + expanded.artCenter.x, y: expanded.artCenter.y)
            : CGPoint(x: width / 2 - compact.size.width / 2 + compact.artCenter.x, y: compact.artCenter.y)

        Color.clear
            .overlay(alignment: .top) {
                CompactLayer(metrics: compact, media: media, visible: isCompact, dimmed: dimmed, onClick: onClick)
                    .frame(width: compact.size.width, height: compact.size.height)
                    .opacity(isCompact ? (dimmed ? 0.55 : 1) : 0)
                    .blur(radius: isCompact ? 0 : 5)
                    .animation(isCompact ? .easeOut(duration: 0.22).delay(0.16) : .easeIn(duration: 0.08), value: isCompact)
                    .animation(.easeInOut(duration: 0.3), value: dimmed)
                    .allowsHitTesting(isCompact)
            }
            .overlay(alignment: .top) {
                ExpandedLayer(metrics: expanded, media: media, active: isExpanded)
                    .frame(width: expanded.size.width, height: expanded.size.height)
                    .opacity(isExpanded ? 1 : 0)
                    .blur(radius: isExpanded ? 0 : 8)
                    .scaleEffect(isExpanded ? 1 : 0.94, anchor: .top)
                    .animation(isExpanded ? .easeOut(duration: 0.3).delay(0.07) : .easeIn(duration: 0.09), value: isExpanded)
                    .allowsHitTesting(isExpanded)
            }
            .overlay(alignment: .topLeading) {
                ArtworkView(media: media, size: artSize, radius: artSize * (isExpanded ? 0.21 : 0.28))
                    .overlay(alignment: .bottomTrailing) {
                        if let icon = media.appIcon, media.artwork != nil {
                            // Scales with the artwork and shows up once it has grown.
                            Image(nsImage: icon).resizable()
                                .frame(width: artSize * 0.36, height: artSize * 0.36)
                                .offset(x: artSize * 0.09, y: artSize * 0.09)
                                .opacity(isExpanded ? 1 : 0)
                                .animation(isExpanded ? .easeOut(duration: 0.2).delay(0.22) : .easeIn(duration: 0.08), value: isExpanded)
                        }
                    }
                    .scaleEffect(presentation.isHidden ? 0.4 : 1)
                    .opacity(presentation.isHidden ? 0 : (dimmed ? 0.55 : 1))
                    .position(artCenter)
                    .allowsHitTesting(false)
            }
            .clipShape(clip)
            .background {
                switch layout.style {
                case .notch:
                    NotchShape(flare: shape.topFlare, bottomRadius: shape.cornerRadius)
                        .fill(.black)
                        .padding(.horizontal, -shape.topFlare)
                        .shadow(color: glowing ? accent.opacity(0.35) : .clear, radius: 10, y: 2)
                case .floating:
                    RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
                        .fill(.black)
                        .shadow(color: .black.opacity(presentation.isHidden ? 0 : 0.35), radius: 12, y: 5)
                        .shadow(color: glowing ? accent.opacity(0.3) : .clear, radius: 9)
                }
            }
            .contentShape(clip)
            // Appearing: solid almost at once while it pops out of the dot.
            // Hiding: shrinks first, then dissolves.
            .opacity(shape.opacity)
            .animation(shape.opacity > 0 ? .easeOut(duration: 0.12) : .easeIn(duration: 0.16).delay(0.14), value: shape.opacity)
    }

    private var clip: AnyShape {
        switch layout.style {
        case .notch: AnyShape(BottomRoundedRect(radius: shape.cornerRadius))
        case .floating: AnyShape(RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous))
        }
    }
}

// MARK: Compact

/// Artwork spot on the left (the artwork itself is drawn by ``IslandBody``), optional title, bars on the right.
struct CompactLayer: View {
    let metrics: CompactMetrics
    let media: NowPlayingModel
    let visible: Bool
    let dimmed: Bool
    let onClick: () -> Void

    var body: some View {
        let playing = visible && !dimmed && media.state?.isPlaying == true
        let accent = media.accent
        ZStack(alignment: .topLeading) {
            Color.clear
            if let title = metrics.titleRect {
                MarqueeText(
                    text: media.state?.title ?? "",
                    font: .system(size: metrics.titleFontSize, weight: .semibold),
                    color: Color(accent.nsColor), active: playing, edgeBlur: true)
                    .frame(width: title.width)
                    .position(x: title.midX, y: title.midY)
            }
            EqualizerView(color: accent.nsColor, active: playing, glow: media.tintFromArtwork && playing)
                .frame(width: metrics.art * 0.72, height: metrics.art * 0.6)
                .position(metrics.barsCenter)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
    }
}

// MARK: Expanded

struct ExpandedLayer: View {
    let metrics: ExpandedMetrics
    let media: NowPlayingModel
    /// Timelines (progress, marquee) only tick while the layer is shown.
    let active: Bool

    var body: some View {
        let s = metrics.s
        let state = media.state
        VStack(spacing: metrics.spacing) {
            HStack(spacing: 12 * s) {
                Color.clear.frame(width: metrics.art, height: metrics.art) // artwork spot
                VStack(alignment: .leading, spacing: 2 * s) {
                    MarqueeText(text: state?.title ?? "", font: .system(size: 14 * s, weight: .semibold), active: active)
                        .contentShape(Rectangle())
                        .onTapGesture { media.openSourceApp() }
                        .help(media.appName.isEmpty ? "" : tr("Открыть ", "Open ") + media.appName)
                    Text(state?.artist ?? "")
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 4 * s)
                PlaybackControls(media: media, scale: s)
            }
            .frame(height: metrics.art)
            ProgressRow(media: media, scale: s, active: active)
                .frame(height: metrics.progressHeight)
        }
        .padding(.horizontal, metrics.padding)
        .frame(width: metrics.size.width, height: metrics.size.height - metrics.inset)
        .padding(.top, metrics.inset)
    }
}

struct PlaybackControls: View {
    let media: NowPlayingModel
    let scale: CGFloat

    var body: some View {
        let playing = media.state?.isPlaying == true
        let seconds = media.skipMode == .seconds
        HStack(spacing: 6 * scale) {
            ControlButton(symbol: seconds ? "gobackward.15" : "backward.fill", size: 15 * scale,
                          label: seconds ? tr("Назад на 15 с", "Back 15 s") : tr("Предыдущий", "Previous")) {
                media.back()
            }
            ControlButton(symbol: playing ? "pause.fill" : "play.fill", size: 21 * scale,
                          label: playing ? tr("Пауза", "Pause") : tr("Играть", "Play")) {
                media.perform(.togglePlayPause)
            }
            ControlButton(symbol: seconds ? "goforward.15" : "forward.fill", size: 15 * scale,
                          label: seconds ? tr("Вперёд на 15 с", "Forward 15 s") : tr("Следующий", "Next")) {
                media.forward()
            }
        }
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white)
                .frame(width: size * 1.9, height: size * 1.9)
                .background(Circle().fill(.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Elapsed time, seek bar, remaining time. Redraws 30 times a second only while expanded and playing.
struct ProgressRow: View {
    let media: NowPlayingModel
    let scale: CGFloat
    var active = true
    @State private var scrub: Double?

    var body: some View {
        let state = media.state
        let playing = active && state?.isPlaying == true && scrub == nil
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let duration = state?.duration
            let position = state.map { PlaybackTimeline.position(of: $0, at: context.date) } ?? 0
            let shown = scrub.map { $0 * (duration ?? 0) } ?? position
            HStack(spacing: 8 * scale) {
                Text(PlaybackTimeline.format(shown))
                    .frame(width: 44 * scale, alignment: .trailing)
                SeekBar(
                    fraction: duration.map { $0 > 0 ? shown / $0 : 0 } ?? 0,
                    accent: Color(media.accent.nsColor),
                    enabled: duration != nil,
                    scrub: $scrub,
                    commit: { fraction in
                        if let duration { media.perform(.seek(fraction * duration)) }
                    })
                Text(duration.map { PlaybackTimeline.format(shown - $0) } ?? "")
                    .frame(width: 44 * scale, alignment: .leading)
            }
            .font(.system(size: 10.5 * scale, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

/// Thin progress bar; click or drag to seek.
struct SeekBar: View {
    let fraction: Double
    let accent: Color
    let enabled: Bool
    @Binding var scrub: Double?
    let commit: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let value = min(max(fraction, 0), 1)
            let active = hovering || scrub != nil
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(accent).frame(width: width * value)
                Circle().fill(.white)
                    .frame(width: active ? 11 : 0, height: active ? 11 : 0)
                    .offset(x: width * value - (active ? 5.5 : 0))
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
            .frame(height: active ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        scrub = min(max(drag.location.x / width, 0), 1)
                    }
                    .onEnded { drag in
                        guard enabled else { return }
                        let final = min(max(drag.location.x / width, 0), 1)
                        commit(final)
                        scrub = nil
                    })
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 14)
        .onHover { hovering = $0 && enabled }
        .accessibilityElement()
        .accessibilityLabel(tr("Позиция", "Position"))
        .accessibilityValue("\(Int(fraction * 100))%")
    }
}

/// Artwork, or a placeholder with the source app's icon or a note.
struct ArtworkView: View {
    let media: NowPlayingModel
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else if let icon = media.appIcon {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(nsImage: icon).resizable().padding(size * 0.12)
                }
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: media.artwork)
    }
}

extension SRGBColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
