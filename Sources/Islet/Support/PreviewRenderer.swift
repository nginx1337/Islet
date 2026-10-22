#if DEBUG
import AppKit
import IsletCore
import SwiftUI

/// Developer aid (debug builds only): renders the island in every state to PNG files,
/// over a fake screen top, without needing screen-recording permission.
/// `Islet --render-preview <dir> [artwork.jpg]`
enum PreviewRenderer {
    static func run(arguments: [String]) {
        let dir = URL(fileURLWithPath: arguments.first ?? "preview")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let artwork = arguments.count > 1 ? try? Data(contentsOf: URL(fileURLWithPath: arguments[1])) : sampleArtwork()

        let state = NowPlayingState(
            bundleID: "com.apple.Music", title: "Midnight City (Extended Version With A Very Long Title)",
            artist: "M83", album: "Hurry Up, We're Dreaming", artworkData: artwork,
            duration: 243, elapsed: 97, timestamp: Date(), rate: 1, isPlaying: true)
        let clock = SystemClock()
        let switcher = SourceSwitcher(primary: StaticSource(state: state), fallback: StaticSource(state: nil), clock: clock)
        let media = NowPlayingModel(switcher: switcher)
        media.start()
        // Let the artwork decode (it runs off the main thread).
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let macBook = ScreenDescriptor(
            id: "builtin", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), backingScale: 2,
            safeAreaTop: 32, auxiliaryLeftWidth: 662, auxiliaryRightWidth: 662, isBuiltIn: true, isMain: true)
        renderSettings(media: media, to: dir)
        let filmScreen = ScreenDescriptor(
            id: "monitor", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), backingScale: 1,
            statusBarThickness: 22, visibleTopInset: 30)
        renderFilmstrip(media: media, screen: filmScreen, name: "monitor-expand", from: .compact(dimmed: false), to: .expanded(.hover), dir: dir)
        renderFilmstrip(media: media, screen: filmScreen, name: "monitor-collapse", from: .expanded(.hover), to: .compact(dimmed: false), dir: dir)
        renderFilmstrip(media: media, screen: filmScreen, name: "monitor-appear", from: .hidden, to: .compact(dimmed: false), dir: dir)
        renderFilmstrip(media: media, screen: macBook, name: "notch-expand", from: .compact(dimmed: false), to: .expanded(.hover), dir: dir)
        renderFilmstrip(media: media, screen: macBook, name: "notch-appear", from: .hidden, to: .compact(dimmed: false), dir: dir)
        let monitor = ScreenDescriptor(
            id: "monitor", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), backingScale: 1,
            statusBarThickness: 22, visibleTopInset: 30)

        let states: [(String, IslandPresentation)] = [
            ("hidden", .hidden), ("compact", .compact(dimmed: false)),
            ("paused", .compact(dimmed: true)), ("expanded", .expanded(.hover))
        ]
        // A short title, as in a real report: the compact island must hug it.
        let shortState = NowPlayingState(
            bundleID: "com.apple.Safari", title: "CREAM SODA - ПОДРУГА", artist: "CREAM SODA",
            artworkData: artwork, duration: 200, elapsed: 30, timestamp: Date(), rate: 1, isPlaying: true)
        let shortMedia = NowPlayingModel(switcher: SourceSwitcher(
            primary: StaticSource(state: shortState), fallback: StaticSource(state: nil), clock: clock))
        shortMedia.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        for (name, screen) in [("monitor-short-title", monitor), ("notch-short-title", macBook)] {
            let layout = IslandLayoutEngine.layout(for: screen, settings: LayoutSettings(compactTitle: true))
            let model = IslandViewModel(layout: layout)
            model.setTitle(shortState.title)
            model.setPresentation(.compact(dimmed: false), animated: false)
            let renderer = ImageRenderer(content: PreviewScene(layout: layout, screen: screen) {
                IslandRootView(model: model, media: shortMedia)
            }.environment(\.staticEqualizer, true))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }

        let variants: [(String, ScreenDescriptor, Bool)] = [
            ("notch", macBook, false), ("monitor", monitor, false),
            ("notch-title", macBook, true), ("monitor-title", monitor, true)
        ]
        for (screenName, screen, title) in variants {
            let layout = IslandLayoutEngine.layout(for: screen, settings: LayoutSettings(compactTitle: title))
            for (stateName, presentation) in states {
                let model = IslandViewModel(layout: layout)
                model.setTitle(media.state?.title)
                model.setPresentation(presentation, animated: false)
                let view = PreviewScene(layout: layout, screen: screen) {
                    IslandRootView(model: model, media: media)
                }
                .environment(\.staticEqualizer, true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { continue }
                let url = dir.appendingPathComponent("\(screenName)-\(stateName).png")
                try? png.write(to: url)
                print(url.path)
            }
        }
    }

    /// Filmstrip of a real animation: an off-screen window snapshotted every 50 ms.
    static func renderFilmstrip(media: NowPlayingModel, screen: ScreenDescriptor, name: String,
                                from: IslandPresentation, to: IslandPresentation, dir: URL) {
        let layout = IslandLayoutEngine.layout(for: screen, settings: LayoutSettings(compactTitle: true))
        let model = IslandViewModel(layout: layout)
        model.setPresentation(from, animated: false)
        let host = NSHostingView(rootView: PreviewScene(layout: layout, screen: screen) {
            IslandRootView(model: model, media: media)
        })
        let size = NSSize(width: layout.panelFrame.width + 160, height: layout.panelFrame.height)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        model.setPresentation(to)
        var frames: [NSBitmapImageRep] = []
        for _ in 0..<12 {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { break }
            host.cacheDisplay(in: host.bounds, to: rep)
            frames.append(rep)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        window.orderOut(nil)
        // Stack the frames vertically into one image.
        let h = Int(size.height), w = Int(size.width)
        let sheet = NSImage(size: NSSize(width: w, height: h * frames.count))
        sheet.lockFocus()
        for (i, rep) in frames.enumerated() {
            rep.draw(in: NSRect(x: 0, y: (frames.count - 1 - i) * h, width: w, height: h))
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let url = dir.appendingPathComponent("film-\(name).png")
            try? png.write(to: url)
            print(url.path)
        }
    }

    /// Settings use AppKit-backed controls, so they are drawn in a real window parked off screen.
    static func renderSettings(media: NowPlayingModel, to dir: URL) {
        let host = NSHostingController(rootView: SettingsView(settings: AppSettings.shared, media: media))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = tr("Islet — настройки", "Islet Settings")
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        window.orderOut(nil)
        let url = dir.appendingPathComponent("settings.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }

    /// Gradient square standing in for album art.
    static func sampleArtwork() -> Data? {
        let size = 512
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [CGColor(srgbRed: 0.98, green: 0.35, blue: 0.45, alpha: 1),
                     CGColor(srgbRed: 0.35, green: 0.2, blue: 0.75, alpha: 1)] as CFArray,
            locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.4, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 170, y: 250, width: 170, height: 170))
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// The top of a screen: wallpaper, menu bar, and the hardware notch for the notch style.
private struct PreviewScene<Island: View>: View {
    let layout: IslandLayout
    let screen: ScreenDescriptor
    @ViewBuilder let island: () -> Island

    var body: some View {
        let size = layout.panelFrame.size
        let width = size.width + 160
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.55, green: 0.68, blue: 0.86), Color(red: 0.85, green: 0.78, blue: 0.86)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.white.opacity(0.55)).frame(height: screen.menuBarHeight)
                .overlay(alignment: .leading) {
                    Text(" Finder   File   Edit   View").font(.system(size: 13, weight: .medium)).padding(.leading, 8)
                }
            if let notch = screen.notchRect {
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
                    .fill(.black).frame(width: notch.width, height: notch.height)
            }
            island().frame(width: size.width, height: size.height)
        }
        .frame(width: width, height: size.height)
        .clipped()
    }
}

/// Emits one fixed state (preview only).
private final class StaticSource: NowPlayingSource {
    let kind = SourceKind.mediaRemote
    let state: NowPlayingState?
    init(state: NowPlayingState?) { self.state = state }
    func start(_ onEvent: @escaping @MainActor (NowPlayingSourceEvent) -> Void) {
        onEvent(.started)
        onEvent(.update(state))
    }
    func stop() {}
    func perform(_ command: PlaybackCommand) {}
}
#endif
