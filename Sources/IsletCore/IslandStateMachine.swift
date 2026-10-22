import Foundation

/// Why the island is expanded.
public enum ExpandReason: Equatable, Sendable {
    case hover
    case click
    case trackChange
    case hotkey
}

/// What the island shows.
public enum IslandPresentation: Equatable, Sendable {
    case hidden
    /// Artwork on the left, equaliser on the right. `dimmed` while paused.
    case compact(dimmed: Bool)
    case expanded(ExpandReason)

    public var isHidden: Bool { self == .hidden }
    public var isExpanded: Bool {
        if case .expanded = self { true } else { false }
    }
}

/// Timings and switches of the state machine.
public struct IslandBehavior: Equatable, Sendable {
    /// How long the island stays open by itself after a new track starts.
    public var trackChangeDuration: TimeInterval = 3
    /// Delay before collapsing once the pointer leaves.
    public var collapseDelay: TimeInterval = 0.4
    /// Paused media hides after this delay; `nil` keeps it visible.
    public var pauseHideDelay: TimeInterval? = 15
    /// "Nothing is playing" must last this long before the island hides.
    /// The adapter briefly reports an empty state when another app takes over.
    public var noMediaGrace: TimeInterval = 0.6
    /// A hotkey expansion closes itself after this delay unless the pointer is on the island.
    public var hotkeyDuration: TimeInterval = 5
    public var expandOnHover = true
    public var expandOnTrackChange = true

    public init() {}
}

/// hidden → compact → expanded(reason), driven by media updates and pointer/hotkey input.
///
/// Every delay goes through the injected ``IslandClock``. No timer exists unless a
/// transition is pending, so a hidden or steady island does no work.
@MainActor
public final class IslandStateMachine {
    public private(set) var presentation: IslandPresentation = .hidden
    public private(set) var media: NowPlayingState?
    public private(set) var isPointerInside = false
    public var behavior: IslandBehavior {
        didSet { if behavior.pauseHideDelay != oldValue.pauseHideDelay { pauseDelayChanged() } }
    }

    /// Called with (old, new) on every presentation change.
    public var onChange: ((IslandPresentation, IslandPresentation) -> Void)?

    private let clock: IslandClock
    private var expansion: ExpandReason?
    private var pauseExpired = false
    private var announcedTrackID: String?
    private var timers: [TimerKind: ScheduledTask] = [:]

    enum TimerKind: Hashable {
        case noMedia, trackChange, collapse, pauseHide, hotkey
    }

    public init(clock: IslandClock, behavior: IslandBehavior = IslandBehavior()) {
        self.clock = clock
        self.behavior = behavior
    }

    /// Number of armed timers; zero means the machine is idle.
    public var activeTimerCount: Int { timers.count }

    // MARK: Inputs

    public func mediaChanged(_ new: NowPlayingState?) {
        guard let new else {
            guard media != nil, timers[.noMedia] == nil else { return }
            arm(.noMedia, after: behavior.noMediaGrace) { [weak self] in
                guard let self else { return }
                self.media = nil
                self.expansion = nil
                self.pauseExpired = false
                self.announcedTrackID = nil
                for kind in [TimerKind.trackChange, .collapse, .pauseHide, .hotkey] { self.disarm(kind) }
                self.recompute()
            }
            return
        }
        disarm(.noMedia)
        let trackChanged = media?.trackID != new.trackID
        // Another item became current: an earlier announcement no longer counts, so coming back
        // to that track (e.g. after a paused video in the browser) announces it again.
        if trackChanged && new.trackID != announcedTrackID { announcedTrackID = nil }
        media = new

        if new.isPlaying {
            disarm(.pauseHide)
            pauseExpired = false
            if new.trackID != announcedTrackID {
                announcedTrackID = new.trackID
                if behavior.expandOnTrackChange, expansion == nil || expansion == .trackChange {
                    expansion = .trackChange
                    arm(.trackChange, after: behavior.trackChangeDuration) { [weak self] in
                        guard let self, self.expansion == .trackChange else { return }
                        self.expansion = (self.isPointerInside && self.behavior.expandOnHover) ? .hover : nil
                        self.recompute()
                    }
                }
            }
        } else {
            if trackChanged {
                pauseExpired = false
                disarm(.pauseHide)
            }
            restartPauseTimerIfNeeded()
        }
        recompute()
    }

    public func pointerEntered() {
        isPointerInside = true
        disarm(.collapse)
        guard !presentation.isHidden, behavior.expandOnHover else { return }
        if expansion == nil || expansion == .trackChange || expansion == .hotkey {
            disarm(.trackChange)
            disarm(.hotkey)
            expansion = .hover
            recompute()
        }
    }

    public func pointerExited() {
        isPointerInside = false
        // A hotkey expansion also closes once the pointer has been on it and leaves
        // (with "expand on hover" off it never turns into a hover expansion).
        guard let expansion, expansion == .hover || expansion == .click || expansion == .hotkey else { return }
        arm(.collapse, after: behavior.collapseDelay) { [weak self] in
            guard let self, !self.isPointerInside else { return }
            self.expansion = nil
            self.recompute()
        }
    }

    public func clicked() {
        guard !presentation.isHidden else { return }
        disarm(.collapse)
        disarm(.trackChange)
        disarm(.hotkey)
        expansion = .click
        recompute()
    }

    /// Toggles the expanded view. Works while paused media is hidden, so it can be resumed.
    public func hotkeyPressed() {
        guard media != nil else { return }
        if presentation.isExpanded {
            collapse()
            return
        }
        expansion = .hotkey
        arm(.hotkey, after: behavior.hotkeyDuration) { [weak self] in
            guard let self, self.expansion == .hotkey, !self.isPointerInside else { return }
            self.expansion = nil
            self.recompute()
        }
        recompute()
    }

    /// Closes the expanded view right away (e.g. after the screen configuration changed).
    public func collapse() {
        for kind in [TimerKind.collapse, .trackChange, .hotkey] { disarm(kind) }
        expansion = nil
        recompute()
    }

    // MARK: Internals

    /// The auto-hide setting changed: turning it off brings hidden paused media back,
    /// a new delay starts counting again from now.
    private func pauseDelayChanged() {
        disarm(.pauseHide)
        if behavior.pauseHideDelay == nil { pauseExpired = false }
        restartPauseTimerIfNeeded()
        recompute()
    }

    private func restartPauseTimerIfNeeded() {
        guard let media, !media.isPlaying, !pauseExpired else {
            disarm(.pauseHide)
            return
        }
        guard let delay = behavior.pauseHideDelay else {
            disarm(.pauseHide)
            return
        }
        guard timers[.pauseHide] == nil else { return }
        arm(.pauseHide, after: delay) { [weak self] in
            guard let self else { return }
            self.pauseExpired = true
            self.recompute()
        }
    }

    private func arm(_ kind: TimerKind, after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        timers[kind]?.cancel()
        timers[kind] = clock.schedule(after: delay) { [weak self] in
            self?.timers[kind] = nil
            action()
        }
    }

    private func disarm(_ kind: TimerKind) {
        timers.removeValue(forKey: kind)?.cancel()
    }

    private func recompute() {
        let next: IslandPresentation
        if let media {
            if let expansion {
                next = .expanded(expansion)
            } else if media.isPlaying || !pauseExpired {
                next = .compact(dimmed: !media.isPlaying)
            } else {
                next = .hidden
            }
        } else {
            next = .hidden
        }
        guard next != presentation else { return }
        let old = presentation
        presentation = next
        onChange?(old, next)
    }
}
