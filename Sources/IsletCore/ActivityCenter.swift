import Foundation

/// Keeps the live activities (timer, stopwatch, power, headphones, file transfers).
///
/// Everything is deadline based: one scheduled task exists only while a timer is running or an
/// activity is about to expire, so with nothing to show the centre does no work at all.
@MainActor
public final class ActivityCenter {
    /// How long a power or headphones notice stays by default (it covers the island meanwhile).
    public static let defaultNoticeDuration: TimeInterval = 4
    /// The range the settings allow for ``noticeDuration``.
    public static let noticeDurationRange: ClosedRange<TimeInterval> = 2...10
    /// How long a finished timer keeps ringing before it goes away.
    public static let finishedDuration: TimeInterval = 10

    /// Called after the set of activities changed (not on every tick).
    public var onChange: (() -> Void)?
    /// A countdown reached zero.
    public var onTimerFinished: (() -> Void)?

    private struct Entry {
        var activity: LiveActivity
        var expiresAt: Date?
    }

    private let clock: IslandClock
    private var entries: [ActivityKind: Entry] = [:]
    private var wakeUp: ScheduledTask?

    /// How long a notice stays, kept inside ``noticeDurationRange``. A notice already on screen keeps
    /// the length it was posted with.
    public var noticeDuration: TimeInterval = ActivityCenter.defaultNoticeDuration {
        didSet {
            let range = Self.noticeDurationRange
            let safe = noticeDuration.isFinite ? noticeDuration : Self.defaultNoticeDuration
            let clamped = min(max(safe, range.lowerBound), range.upperBound)
            if clamped != noticeDuration { noticeDuration = clamped }
        }
    }

    public init(clock: IslandClock) {
        self.clock = clock
    }

    /// All activities, most important first.
    public var activities: [LiveActivity] {
        entries.values.map(\.activity).sorted { a, b in
            if a.content.priority != b.content.priority { return a.content.priority > b.content.priority }
            if a.postedAt != b.postedAt { return a.postedAt > b.postedAt }
            return a.id < b.id
        }
    }

    /// The one shown in the capsule.
    public var current: LiveActivity? { activities.first }

    public func activity(_ kind: ActivityKind) -> LiveActivity? { entries[kind]?.activity }

    // MARK: Timer

    /// Starts (or restarts) the countdown.
    public func startTimer(duration: TimeInterval) {
        let now = clock.now
        set(.countdown(CountdownTimer(duration: duration, startingAt: now)), expiresAt: nil)
    }

    /// Pauses a running timer, resumes a paused one, dismisses a finished one.
    public func toggleTimer() {
        refresh() // a timer that has just ended counts as finished, not as running
        guard case .countdown(var timer) = entries[.timer]?.activity.content else { return }
        let now = clock.now
        if timer.isFinished {
            remove(.timer)
            return
        }
        if timer.isRunning { timer.pause(at: now) } else { timer.resume(at: now) }
        set(.countdown(timer), expiresAt: nil)
    }

    // MARK: Stopwatch

    public func startStopwatch() {
        set(.stopwatch(Stopwatch(startingAt: clock.now)), expiresAt: nil)
    }

    public func toggleStopwatch() {
        guard case .stopwatch(var watch) = entries[.stopwatch]?.activity.content else { return }
        let now = clock.now
        if watch.isRunning { watch.pause(at: now) } else { watch.resume(at: now) }
        set(.stopwatch(watch), expiresAt: nil)
    }

    // MARK: Other activities

    /// A short notice (power, headphones) that goes away by itself.
    public func postNotice(_ content: ActivityContent) {
        set(content, expiresAt: clock.now.addingTimeInterval(noticeDuration))
    }

    /// An activity that stays until it is removed (file transfers). An unchanged update is ignored.
    public func update(_ content: ActivityContent) {
        if entries[content.kind]?.activity.content == content { return }
        set(content, expiresAt: nil)
    }

    public func remove(_ kind: ActivityKind) {
        guard entries.removeValue(forKey: kind) != nil else { return }
        reschedule()
        onChange?()
    }

    /// Dismisses the activity the user tapped away.
    public func dismiss(_ kind: ActivityKind) {
        remove(kind)
    }

    /// Re-checks every deadline against the clock. Also called after the Mac wakes from sleep,
    /// when the scheduled task may have been late.
    public func refresh() {
        let now = clock.now
        var changed = false
        var finished = false
        for (kind, entry) in entries {
            var entry = entry
            if case .countdown(var timer) = entry.activity.content, timer.hasEnded(at: now) {
                timer.finish()
                entry.activity.content = .countdown(timer)
                entry.expiresAt = now.addingTimeInterval(Self.finishedDuration)
                entries[kind] = entry
                changed = true
                finished = true
            }
            if let expiresAt = entry.expiresAt, expiresAt <= now {
                entries[kind] = nil
                changed = true
            }
        }
        reschedule()
        if changed { onChange?() }
        if finished { onTimerFinished?() }
    }

    // MARK: Internals

    private func set(_ content: ActivityContent, expiresAt: Date?) {
        entries[content.kind] = Entry(activity: LiveActivity(content: content, postedAt: clock.now), expiresAt: expiresAt)
        reschedule()
        onChange?()
    }

    private func reschedule() {
        wakeUp?.cancel()
        wakeUp = nil
        var next: Date?
        for entry in entries.values {
            var deadline = entry.expiresAt
            if case .countdown(let timer) = entry.activity.content, case .running(let end) = timer.phase {
                deadline = min(deadline ?? end, end)
            }
            if let deadline { next = min(next ?? deadline, deadline) }
        }
        guard let next else { return }
        let delay = max(0.05, next.timeIntervalSince(clock.now))
        wakeUp = clock.schedule(after: delay) { [weak self] in
            self?.wakeUp = nil
            self?.refresh()
        }
    }
}
