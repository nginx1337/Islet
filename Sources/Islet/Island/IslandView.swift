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
    /// The live activity: a bubble that comes out of the island's edge, the island itself when nothing
    /// else plays, its card when clicked open, or a notice that drops out of the island.
    @ViewBuilder
    var satellite: some View {
        let mode = model.satelliteMode
        ZStack(alignment: .topLeading) {
            if let activity = model.activities.current, let mode, let shape = model.satelliteShape {
                SatelliteView(
                    activity: activity, activities: model.activities, mode: mode, layout: model.layout,
                    shape: shape, main: model.shape, onTap: { model.onSatelliteClick?() })
                    .frame(width: shape.frame.width, height: shape.frame.height)
                    // A notice only shows something: clicks reach the island and the menu bar under it.
                    .allowsHitTesting(mode != .notice)
                    .offset(x: shape.frame.minX, y: shape.frame.minY)
                    .transition(Self.transition(for: mode))
            }
        }
        .frame(width: model.layout.panelFrame.width, height: model.layout.panelFrame.height, alignment: .topLeading)
        // A new activity springs in; going away has its own calmer animation in each transition.
        // Opening and closing the card animate where they happen (IslandController), and a change
        // of the island underneath moves the activity with the island's own spring.
        .animation(IslandMotion.satellite, value: model.activities.current?.kind)
    }

    /// A bubble comes out of the island like a drop and goes back into it; cards drop down from the
    /// island and fold back up into it; the activity island takes the island's place.
    static func transition(for mode: SatelliteMode) -> AnyTransition {
        switch mode {
        case .bubble:
            .emerge
        case .expanded, .notice:
            .asymmetric(
                insertion: .scale(scale: 0.6, anchor: .top).combined(with: .opacity),
                removal: .scale(scale: 0.5, anchor: .top).combined(with: .opacity).animation(IslandMotion.dismiss))
        case .island:
            .asymmetric(
                insertion: .scale(scale: 0.6, anchor: .center).combined(with: .opacity),
                removal: .scale(scale: 0.6, anchor: .center).combined(with: .opacity).animation(IslandMotion.dismiss))
        }
    }
}

/// The faint light edge around the black shapes, as on the iPhone over a dark background.
enum IslandOutline {
    static let width: CGFloat = 1
    static let opacity: Double = 0.17
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
        let inset = IslandLayout.titleInset * layout.scale
        art = (layout.style == .floating || layout.isDrawnNotch)
            ? max(14, min((h * 0.64).rounded(), 24))
            : max(14, min(h - 10, 24))
        switch layout.style {
        case .notch where layout.isDrawnNotch:
            ear = layout.compactEar
            titleRect = layout.compactTitle ? CGRect(x: ear + inset, y: 0, width: max(0, frame.width - 2 * (ear + inset)), height: h) : nil
        case .notch:
            let side = max(0, (frame.width - layout.notchWidth) / 2)
            ear = min(side, layout.compactEar)
            titleRect = layout.compactTitle && side - ear > 24
                ? CGRect(x: ear, y: 0, width: side - ear - 8, height: h) : nil
        case .floating:
            ear = layout.compactEar
            titleRect = layout.compactTitle ? CGRect(x: ear + inset, y: 0, width: max(0, frame.width - 2 * (ear + inset)), height: h) : nil
        }
        titleFontSize = IslandViewModel.compactTitleFontSize(for: layout)
        if layout.style == .floating || layout.isDrawnNotch {
            // The artwork and the bars sit on the centres of the rounded ends, so the gap around
            // them is the same at the top, the bottom and the side.
            artCenter = CGPoint(x: h / 2, y: h / 2)
            barsCenter = CGPoint(x: frame.width - h / 2, y: h / 2)
        } else {
            artCenter = CGPoint(x: ear / 2, y: h / 2)
            barsCenter = CGPoint(x: frame.width - ear / 2, y: h / 2)
        }
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
    /// Room for the progress bar at its thickest, and for a comfortable target to grab.
    var progressHeight: CGFloat { 16 * s }
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
                    .animation(isCompact ? IslandMotion.fadeIn(delay: 0.10) : IslandMotion.fadeOut, value: isCompact)
                    .animation(.easeInOut(duration: 0.3), value: dimmed)
                    .allowsHitTesting(isCompact)
            }
            .overlay(alignment: .top) {
                ExpandedLayer(metrics: expanded, media: media, active: isExpanded)
                    .frame(width: expanded.size.width, height: expanded.size.height)
                    .opacity(isExpanded ? 1 : 0)
                    .animation(isExpanded ? IslandMotion.fadeIn() : IslandMotion.fadeOut, value: isExpanded)
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
                                .animation(isExpanded ? IslandMotion.fadeIn(delay: 0.2) : IslandMotion.fadeOut, value: isExpanded)
                        }
                    }
                    .scaleEffect(presentation.isHidden ? 0.85 : 1)
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
                        .overlay {
                            // Like the iPhone on a dark wallpaper: a faint edge, along the sides and the bottom only.
                            NotchShape(flare: shape.topFlare, bottomRadius: shape.cornerRadius, closed: false)
                                .stroke(Color.white.opacity(outlineOpacity), lineWidth: IslandOutline.width)
                        }
                        .padding(.horizontal, -shape.topFlare)
                case .floating:
                    RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
                        .fill(.black)
                        .overlay {
                            RoundedRectangle(cornerRadius: shape.cornerRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(outlineOpacity), lineWidth: IslandOutline.width)
                        }
                        .shadow(color: .black.opacity(presentation.isHidden ? 0 : 0.3), radius: 10, y: 4)
                }
            }
            .contentShape(clip)
            // Appearing: solid almost at once while it pops out of the dot.
            // Hiding: shrinks first, then dissolves.
            .opacity(shape.opacity)
            .animation(shape.opacity > 0 ? .easeOut(duration: 0.12) : .easeIn(duration: 0.16).delay(0.14), value: shape.opacity)
    }

    private var outlineOpacity: Double {
        layout.outline && !presentation.isHidden ? IslandOutline.opacity : 0
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
                    color: Color(accent.nsColor), active: playing)
                    .frame(width: title.width)
                    .position(x: title.midX, y: title.midY)
            }
            EqualizerView(color: accent.nsColor, active: playing)
                .frame(width: metrics.art * 0.95, height: metrics.art * 0.72)
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
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(IslandMotion.press, value: configuration.isPressed)
    }
}

/// Elapsed time, progress bar, remaining time, as in Apple's Now Playing. Redraws 30 times a second
/// only while expanded and playing, and not while the bar is held.
struct ProgressRow: View {
    let media: NowPlayingModel
    let scale: CGFloat
    var active = true
    /// Where the held bar points (0…1); nil when it is not held.
    @State private var scrub: Double?

    var body: some View {
        let state = media.state
        let playing = active && state?.isPlaying == true && scrub == nil
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { context in
            let duration = state?.duration
            // A timeline that was paused (bar held, island closed) can hand back its last date once
            // it runs again; the clock never goes back, so neither does the bar.
            let now = max(context.date, Date())
            let position = state.map { PlaybackTimeline.position(of: $0, at: now) } ?? 0
            let shown = scrub.map { $0 * (duration ?? 0) } ?? position
            // Hour-long items need room for "−1:02:03".
            let labelWidth: CGFloat = ((duration ?? 0) >= 3600 ? 52 : 40) * scale
            let elapsedText = PlaybackTimeline.format(shown)
            // Always with a minus, down to "−0:00" at the very end, as on the iPhone.
            let remainingText = duration.map { "−" + PlaybackTimeline.format(max(0, $0 - shown)) } ?? ""
            let valueText = duration.map {
                tr("\(elapsedText) из \(PlaybackTimeline.format($0))", "\(elapsedText) of \(PlaybackTimeline.format($0))")
            } ?? ""
            HStack(spacing: 10 * scale) {
                timeLabel(elapsedText, width: labelWidth, alignment: .trailing)
                SeekBar(
                    fraction: duration.map { $0 > 0 ? shown / $0 : 0 } ?? 0,
                    enabled: active && duration != nil,
                    scale: scale,
                    valueText: valueText,
                    scrub: $scrub,
                    commit: { fraction in
                        if let duration { media.perform(.seek(fraction * duration)) }
                    })
                timeLabel(remainingText, width: labelWidth, alignment: .leading)
            }
        }
        // The bar cannot stay held once the island has closed under the pointer.
        .onChange(of: active) { _, isActive in
            if !isActive { scrub = nil }
        }
    }

    /// The times brighten while the bar is held, as on the iPhone.
    private func timeLabel(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 11 * scale, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // Only the colour fades; the digits themselves change at once.
            .animation(IslandMotion.hover) { $0.foregroundStyle(.white.opacity(scrub == nil ? 0.5 : 0.85)) }
            .frame(width: width, alignment: alignment)
            .accessibilityHidden(true)
    }
}

/// Progress bar in the style of Apple's Now Playing: a white fill on a faint track, no knob.
/// It grows thicker under the pointer and thicker still while held. Click or drag to seek; dragged
/// past an end it stretches a little that way, like rubber, and springs back when let go.
struct SeekBar: View {
    let fraction: Double
    let enabled: Bool
    let scale: CGFloat
    /// What VoiceOver reads as the value ("1:05 of 3:20").
    let valueText: String
    @Binding var scrub: Double?
    let commit: (Double) -> Void
    @State private var hovering = false
    /// The bar is held. Gesture state resets by itself when the drag ends or is cancelled (say, the
    /// island closed under the pointer), so the bar never stays stuck in the held look.
    @GestureState private var hold: Hold? = nil

    nonisolated struct Hold: Sendable {
        /// Position under the pointer, 0…1.
        var fraction: Double
        /// How far the bar is pulled past an end (negative: past the start).
        var stretch: CGFloat
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let held = hold != nil
            let value = hold?.fraction ?? min(max(fraction, 0), 1)
            let stretch = hold?.stretch ?? 0
            let pulled = width + abs(stretch)
            // Thicker under the pointer and while held; a little thinner while stretched.
            let thickness: CGFloat = (held ? 10 : (hovering ? 7 : 5)) * scale
            let squeeze: CGFloat = 1 - 0.25 * abs(stretch) / (Scrubber.maxStretch * scale)
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(held ? 0.28 : 0.2))
                Rectangle().fill(.white.opacity(held ? 1 : 0.92))
                    .frame(width: pulled * value)
            }
            .frame(width: pulled, height: thickness * squeeze)
            // The fill is cut by the track, so its start is round and its end is straight.
            .clipShape(Capsule())
            .offset(x: min(0, stretch))
            .frame(width: width, height: geometry.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(drag(width: width))
            .animation(IslandMotion.scrub, value: held)
            .animation(IslandMotion.hover, value: hovering)
        }
        .onHover { hovering = $0 && enabled }
        // A collapsing island takes the bar away without telling it the pointer left.
        .onChange(of: enabled) { _, isEnabled in
            if !isEnabled { hovering = false }
        }
        .onChange(of: hold?.fraction) { _, new in scrub = new }
        .accessibilityElement()
        .accessibilityLabel(tr("Позиция", "Position"))
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: commit(min(1, fraction + 0.05))
            case .decrement: commit(max(0, fraction - 0.05))
            @unknown default: break
            }
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($hold) { drag, hold, _ in
                guard enabled else { return }
                let x = drag.location.x
                hold = Hold(
                    fraction: Scrubber.fraction(atX: x, width: width),
                    stretch: Scrubber.stretch(
                        forOvershoot: Scrubber.overshoot(atX: x, width: width),
                        limit: Scrubber.maxStretch * scale))
            }
            .onEnded { drag in
                guard enabled else { return }
                commit(Scrubber.fraction(atX: drag.location.x, width: width))
            }
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
