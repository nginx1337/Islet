import CoreGraphics
import Foundation

/// Keeps the position the user seeked to until the player confirms it.
///
/// After a seek the player often sends one or two more updates that still carry the old position
/// (browsers especially, and any update about something else, such as the artwork). Shown as they
/// come, they make the bar jump back and then forward again. While the hold lasts, such an update
/// keeps its other news but shows the position the user chose, counted on from the seek.
public struct SeekHold: Equatable, Sendable {
    /// The player has this long to confirm the seek; after that its own position wins again
    /// (it may have refused the seek).
    public static let timeout: TimeInterval = 2.5
    /// A reported position this close to the expected one confirms the seek.
    public static let tolerance: TimeInterval = 1.5

    public let trackID: String
    public let startedAt: Date
    private let duration: TimeInterval?
    /// Where the hold says playback is at `anchorDate`, moving at `rate` from there.
    private var anchor: TimeInterval
    private var anchorDate: Date
    private var rate: Double
    public private(set) var isFinished = false

    /// A seek to `target` in the track of `state`, made at `now`.
    public init(target: TimeInterval, state: NowPlayingState, at now: Date) {
        trackID = state.trackID
        startedAt = now
        duration = state.duration
        let safe = target.isFinite ? target : 0
        anchor = max(0, state.duration.map { min(safe, $0) } ?? safe)
        anchorDate = now
        rate = state.isPlaying ? state.rate : 0
    }

    /// Where playback should be at `now` if the player did what was asked.
    public func expected(at now: Date) -> TimeInterval {
        var position = anchor + rate * max(0, now.timeIntervalSince(anchorDate))
        if let duration { position = min(position, duration) }
        return max(0, position)
    }

    /// `state` showing the expected position: what the island shows right after the seek.
    public func applied(to state: NowPlayingState, at now: Date) -> NowPlayingState {
        var shown = state
        shown.elapsed = expected(at: now)
        shown.timestamp = now
        return shown
    }

    /// What to show for an update from the player. Ends the hold once the player confirms the
    /// position, plays another track, or takes too long.
    public mutating func reconcile(_ incoming: NowPlayingState, at now: Date) -> NowPlayingState {
        guard !isFinished else { return incoming }
        if incoming.trackID != trackID || now.timeIntervalSince(startedAt) > Self.timeout {
            isFinished = true
            return incoming
        }
        // Count on from where the hold says playback is, at the player's new pace
        // (a player may pause for a moment while it buffers the new spot).
        let position = expected(at: now)
        anchor = position
        anchorDate = now
        rate = incoming.isPlaying ? incoming.rate : 0
        if incoming.elapsed != nil,
           abs(PlaybackTimeline.position(of: incoming, at: now) - position) <= Self.tolerance {
            isFinished = true
            return incoming
        }
        return applied(to: incoming, at: now)
    }
}

/// Pointer maths of the progress bar: the position under the pointer, and how far the bar
/// stretches when the pointer is dragged past one of its ends.
public enum Scrubber {
    /// The bar stretches at most this far past an end (points, scale 1).
    public static let maxStretch: CGFloat = 6

    /// 0…1 for a pointer at `x` on a bar `width` wide.
    public static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    /// How far the pointer is past the bar's ends: negative before the start, positive after the end.
    public static func overshoot(atX x: CGFloat, width: CGFloat) -> CGFloat {
        guard x.isFinite else { return 0 }
        if x < 0 { return x }
        if x > width { return x - max(0, width) }
        return 0
    }

    /// Rubber band, as at the edge of a scroll view: the bar follows the pointer less and less
    /// and never stretches more than `limit`. Keeps the sign of `overshoot`.
    public static func stretch(forOvershoot overshoot: CGFloat, limit: CGFloat = maxStretch) -> CGFloat {
        guard overshoot.isFinite, overshoot != 0, limit > 0 else { return 0 }
        let pulled = limit * (1 - 1 / (abs(overshoot) * 0.55 / limit + 1))
        return overshoot < 0 ? -pulled : pulled
    }
}
