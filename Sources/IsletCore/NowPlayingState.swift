import Foundation

/// Everything the island knows about the current media session.
///
/// `elapsed` is the position at `timestamp`; the live position is interpolated
/// with ``PlaybackTimeline`` instead of being polled.
public struct NowPlayingState: Equatable, Sendable {
    /// Bundle identifier of the app that plays (for browsers: the browser, not its WebKit helper).
    public var bundleID: String?
    public var title: String
    public var artist: String
    public var album: String
    /// Encoded image (JPEG/PNG) as delivered by the source. Decoding and downscaling happen elsewhere.
    public var artworkData: Data?
    /// Remote artwork (Spotify fallback only). Downloaded once and cached.
    public var artworkURL: URL?
    public var duration: TimeInterval?
    public var elapsed: TimeInterval?
    public var timestamp: Date?
    public var rate: Double
    public var isPlaying: Bool

    public init(
        bundleID: String? = nil, title: String, artist: String = "", album: String = "",
        artworkData: Data? = nil, artworkURL: URL? = nil,
        duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, timestamp: Date? = nil,
        rate: Double = 1, isPlaying: Bool
    ) {
        self.bundleID = bundleID
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.artworkURL = artworkURL
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.rate = rate
        self.isPlaying = isPlaying
    }

    /// Identity of the track, used to detect "the track changed" (artwork and position are ignored).
    public var trackID: String {
        [bundleID ?? "", title, artist, album].joined(separator: "\u{1F}")
    }

    /// Key for the artwork cache: the same picture is decoded once.
    public var artworkKey: String? {
        if let artworkURL { return artworkURL.absoluteString }
        guard let artworkData else { return nil }
        var hasher = Hasher()
        hasher.combine(artworkData)
        return "\(trackID)#\(artworkData.count)#\(hasher.finalize())"
    }
}

/// Commands the island can send to the player.
public enum PlaybackCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case seek(TimeInterval)

    /// Command ID understood by `mediaremote-adapter.pl send` (MediaRemote `MRCommand`).
    public var adapterSendID: Int? {
        switch self {
        case .play: 0
        case .pause: 1
        case .togglePlayPause: 2
        case .nextTrack: 4
        case .previousTrack: 5
        case .seek: nil
        }
    }

    /// Full argument list for the adapter script after the framework path.
    public var adapterArguments: [String] {
        switch self {
        case .seek(let seconds):
            ["seek", String(Int64((max(0, seconds) * 1_000_000).rounded()))]
        default:
            ["send", String(adapterSendID ?? 2)]
        }
    }
}
