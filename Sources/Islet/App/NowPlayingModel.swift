import AppKit
import IsletCore
import Observation

/// What is playing, shared by every island: state, decoded artwork, accent colour, source app.
@Observable
final class NowPlayingModel {
    private(set) var state: NowPlayingState?
    private(set) var artwork: NSImage?
    private(set) var artworkAccent: SRGBColor?
    private(set) var appIcon: NSImage?
    private(set) var appName = ""
    private(set) var sourceStatus: SourceSwitcher.Status = .starting
    var tintFromArtwork = true
    /// Track skip, or ±15 s for items whose player has no next/previous.
    private(set) var skipMode: SkipMode = .tracks

    @ObservationIgnored var onStateChange: ((NowPlayingState?) -> Void)?
    @ObservationIgnored private let switcher: SourceSwitcher
    @ObservationIgnored private var cache = LRUCache<String, ArtworkEntry>(capacity: 20)
    @ObservationIgnored private var loadingKey: String?
    @ObservationIgnored private var artworkTrackID: String?
    @ObservationIgnored private var secondsOnlyTracks = Set<String>()
    @ObservationIgnored private var pendingNextCheck: DispatchWorkItem?
    @ObservationIgnored private let downloads: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    struct ArtworkEntry {
        let image: NSImage
        let accent: SRGBColor?
    }

    init(switcher: SourceSwitcher) {
        self.switcher = switcher
        switcher.onState = { [weak self] in self?.apply($0) }
        switcher.onStatus = { [weak self] status in
            self?.sourceStatus = status
            Log.source.info("source status: \(String(describing: status), privacy: .public)")
        }
    }

    func start() { switcher.start() }
    func stop() { switcher.stop() }
    func retryPrimarySource() { switcher.retryPrimary() }

    /// Accent for the equaliser and the title.
    var accent: SRGBColor {
        tintFromArtwork ? (artworkAccent ?? .neutral) : .neutral
    }

    func perform(_ command: PlaybackCommand) {
        switcher.perform(command)
        // Seek feels instant: move the local position now, the player confirms a moment later.
        if case .seek(let seconds) = command, var state {
            state.elapsed = seconds
            state.timestamp = Date()
            apply(state)
        }
    }

    /// "Back": restart the track after 3 s, otherwise the previous track (or −15 s).
    func back() {
        guard let state else { return }
        let position = PlaybackTimeline.position(of: state, at: Date())
        perform(SkipPlanner.back(position: position, mode: skipMode))
    }

    /// "Forward": the next track. If the player ignores it (a single video in a browser), skip 15 s
    /// instead and switch both buttons to ±15 s for this item.
    func forward() {
        guard let state else { return }
        let position = PlaybackTimeline.position(of: state, at: Date())
        let command = SkipPlanner.forward(position: position, duration: state.duration, mode: skipMode)
        perform(command)
        guard command == .nextTrack else { return }
        let trackID = state.trackID
        pendingNextCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let now = self.state else { return }
                let after = PlaybackTimeline.position(of: now, at: Date())
                guard SkipPlanner.nextWasIgnored(
                    sameTrack: now.trackID == trackID, isPlaying: now.isPlaying,
                    positionBefore: position, positionAfter: after)
                else { return }
                Log.source.info("next track not supported here, skipping 15 s")
                self.secondsOnlyTracks.insert(trackID)
                self.skipMode = .seconds
                self.perform(.seek(SkipPlanner.clampedForward(position: after, duration: now.duration)))
            }
        }
        pendingNextCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + SkipPlanner.nextTimeout, execute: check)
    }

    func openSourceApp() {
        guard let bundle = state?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Updates

    private func apply(_ new: NowPlayingState?) {
        let oldBundle = state?.bundleID
        state = new
        let mode: SkipMode = new.map { secondsOnlyTracks.contains($0.trackID) ? .seconds : .tracks } ?? .tracks
        if mode != skipMode { skipMode = mode }
        if new?.bundleID != oldBundle { updateApp(new?.bundleID) }
        updateArtwork(for: new)
        onStateChange?(new)
    }

    private func updateApp(_ bundle: String?) {
        guard let bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            appIcon = nil
            appName = ""
            return
        }
        appIcon = Self.bitmap(NSWorkspace.shared.icon(forFile: url.path), points: 32)
        appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Workspace icons hold many representations drawn on demand; one small @2x bitmap is enough here.
    private static func bitmap(_ icon: NSImage, points: CGFloat) -> NSImage {
        let pixels = Int(points * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return icon }
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func updateArtwork(for state: NowPlayingState?) {
        guard let state else {
            artworkTrackID = nil
            setArtwork(nil)
            return
        }
        if state.trackID != artworkTrackID {
            artworkTrackID = state.trackID
            // A new track never keeps the previous cover: show the placeholder until its own
            // artwork is decoded (or for good, if decoding or the download fails).
            if state.artworkKey.map({ cache.value(for: $0) == nil }) ?? true {
                setArtwork(nil)
            }
        }
        // Same track and the artwork briefly vanished (happens while seeking): keep the picture.
        guard let key = state.artworkKey else { return }
        if let entry = cache.value(for: key) {
            loadingKey = key
            setArtwork(entry)
            return
        }
        guard loadingKey != key else { return }
        loadingKey = key
        if let data = state.artworkData {
            decode(data, key: key)
        } else if let url = state.artworkURL {
            download(url, key: key)
        }
    }

    private func setArtwork(_ entry: ArtworkEntry?) {
        artwork = entry?.image
        artworkAccent = entry?.accent
        if entry == nil { loadingKey = nil }
    }

    /// Downscales to 256 px and finds the accent off the main thread.
    private func decode(_ data: Data, key: String) {
        Task.detached(priority: .userInitiated) {
            let result = Decoded(data: data)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let image = result.image else { return }
                let entry = ArtworkEntry(
                    image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
                    accent: result.accent)
                self.cache.insert(entry, for: key)
                if self.loadingKey == key { self.setArtwork(entry) }
            }
        }
    }

    /// The only network request in the app: Spotify artwork in fallback mode. Cached like the rest.
    private func download(_ url: URL, key: String) {
        let session = downloads
        Task { [weak self] in
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000
            else { return }
            self?.decode(data, key: key)
        }
    }

    nonisolated private struct Decoded: @unchecked Sendable {
        let image: CGImage?
        let accent: SRGBColor?
        init(data: Data) {
            image = ArtworkDecoder.thumbnail(from: data)
            accent = image.flatMap(DominantColor.accent(of:))
        }
    }
}
