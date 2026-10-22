import Foundation

/// What the back/forward buttons do for the current item.
public enum SkipMode: Equatable, Sendable {
    /// Previous/next track.
    case tracks
    /// ±15 seconds: for items whose player has no next/previous (e.g. a single video in a browser).
    case seconds
}

/// Turns a back/forward press into a command, like a hardware player would.
public enum SkipPlanner {
    /// "Back" after this many seconds restarts the track instead of going to the previous one.
    public static let restartThreshold: TimeInterval = 3
    public static let step: TimeInterval = 15
    /// If "next" did not change the track within this time, the player does not support it.
    public static let nextTimeout: TimeInterval = 1.5

    public static func back(position: TimeInterval, mode: SkipMode) -> PlaybackCommand {
        switch mode {
        case .seconds: .seek(max(0, position - step))
        case .tracks: position > restartThreshold ? .seek(0) : .previousTrack
        }
    }

    public static func forward(position: TimeInterval, duration: TimeInterval?, mode: SkipMode) -> PlaybackCommand {
        switch mode {
        case .seconds: .seek(clampedForward(position: position, duration: duration))
        case .tracks: .nextTrack
        }
    }

    /// Target of a 15-second skip, never past the last half second.
    public static func clampedForward(position: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        let target = position + step
        guard let duration, duration > 0 else { return target }
        return max(0, min(target, duration - 0.5))
    }
}
