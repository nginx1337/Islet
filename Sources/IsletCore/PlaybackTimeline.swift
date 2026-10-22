import Foundation

/// Live playback position without polling the player:
/// `position = elapsed + rate × (now − timestamp)`, clamped to `0…duration`.
public enum PlaybackTimeline {
    public static func position(of state: NowPlayingState, at now: Date) -> TimeInterval {
        let base = state.elapsed ?? 0
        let rate = state.isPlaying ? state.rate : 0
        var position = base
        if let timestamp = state.timestamp, rate != 0 {
            position += rate * now.timeIntervalSince(timestamp)
        }
        if let duration = state.duration { position = min(position, duration) }
        return max(0, position)
    }

    /// 0…1, or nil when the duration is unknown (live streams).
    public static func progress(of state: NowPlayingState, at now: Date) -> Double? {
        guard let duration = state.duration, duration > 0 else { return nil }
        return position(of: state, at: now) / duration
    }

    /// "1:05", "12:00", "1:02:03". Negative values get a leading minus (remaining time).
    public static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "–:––" }
        let negative = seconds < 0
        let total = Int(abs(seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let body = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        return negative ? "−" + body : body
    }
}
