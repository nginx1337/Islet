import Foundation

public enum SourceKind: String, Sendable {
    /// MediaRemote through `/usr/bin/perl` + mediaremote-adapter: any player, browsers, podcasts.
    case mediaRemote
    /// Apple Music and Spotify through their notifications and AppleScript.
    case musicSpotify
}

public enum NowPlayingSourceEvent: Equatable, Sendable {
    /// The source works (first data arrived), even if nothing is playing.
    case started
    case update(NowPlayingState?)
    /// The source stopped working and will not recover by itself.
    case failed(String)
}

/// A provider of now-playing updates and a way to control the player.
@MainActor
public protocol NowPlayingSource: AnyObject {
    var kind: SourceKind { get }
    func start(_ onEvent: @escaping @MainActor (NowPlayingSourceEvent) -> Void)
    func stop()
    func perform(_ command: PlaybackCommand)
}

/// Runs the primary source and switches to the fallback when the primary does not start
/// in time or keeps failing. A crash after it worked gets a couple of restarts first.
@MainActor
public final class SourceSwitcher {
    public enum Status: Equatable, Sendable {
        case starting
        case primary
        case fallback(reason: String)
        case unavailable(reason: String)

        public var isFallback: Bool {
            if case .fallback = self { true } else { false }
        }
    }

    public struct Options: Sendable {
        public var startupTimeout: TimeInterval = 5
        public var maxRestarts = 2
        public var restartDelay: TimeInterval = 1
        /// A primary that ran this long gets its restart budget back.
        public var healthyRunTime: TimeInterval = 60
        public init() {}
    }

    public private(set) var status: Status = .starting
    public private(set) var state: NowPlayingState?
    public var onState: ((NowPlayingState?) -> Void)?
    public var onStatus: ((Status) -> Void)?

    public let primary: NowPlayingSource
    public let fallback: NowPlayingSource
    private let clock: IslandClock
    private let options: Options
    private var active: NowPlayingSource?
    private var generation = 0
    private var restarts = 0
    private var primaryStartedAt: Date?
    private var timeout: ScheduledTask?
    private var restartTask: ScheduledTask?

    public init(primary: NowPlayingSource, fallback: NowPlayingSource, clock: IslandClock, options: Options = Options()) {
        self.primary = primary
        self.fallback = fallback
        self.clock = clock
        self.options = options
    }

    public var activeKind: SourceKind? { active?.kind }

    public func start() {
        restarts = 0
        startPrimary()
    }

    public func stop() {
        generation += 1
        timeout?.cancel()
        restartTask?.cancel()
        active?.stop()
        active = nil
    }

    public func perform(_ command: PlaybackCommand) {
        active?.perform(command)
    }

    /// Gives the primary another chance (e.g. from settings after a macOS update).
    public func retryPrimary() {
        stop()
        restarts = 0
        startPrimary()
    }

    private func startPrimary() {
        generation += 1
        let token = generation
        active = primary
        primaryStartedAt = nil
        setStatus(.starting)
        timeout?.cancel()
        timeout = clock.schedule(after: options.startupTimeout) { [weak self] in
            guard let self, self.generation == token, self.primaryStartedAt == nil else { return }
            self.switchToFallback(reason: "timeout")
        }
        primary.start { [weak self] event in
            guard let self, self.generation == token else { return }
            self.handlePrimary(event)
        }
    }

    private func handlePrimary(_ event: NowPlayingSourceEvent) {
        switch event {
        case .started:
            if primaryStartedAt == nil {
                primaryStartedAt = clock.now
                timeout?.cancel()
                setStatus(.primary)
            }
        case .update(let new):
            if primaryStartedAt == nil { handlePrimary(.started) }
            publish(new)
        case .failed(let reason):
            primary.stop()
            generation += 1
            timeout?.cancel()
            if let startedAt = primaryStartedAt, clock.now.timeIntervalSince(startedAt) >= options.healthyRunTime {
                restarts = 0
            }
            if primaryStartedAt != nil, restarts < options.maxRestarts {
                restarts += 1
                setStatus(.starting)
                restartTask = clock.schedule(after: options.restartDelay) { [weak self] in
                    self?.startPrimary()
                }
            } else {
                switchToFallback(reason: reason)
            }
        }
    }

    private func switchToFallback(reason: String) {
        primary.stop()
        generation += 1
        let token = generation
        active = fallback
        setStatus(.fallback(reason: reason))
        fallback.start { [weak self] event in
            guard let self, self.generation == token else { return }
            switch event {
            case .started: break
            case .update(let new): self.publish(new)
            case .failed(let why):
                self.fallback.stop()
                self.active = nil
                self.setStatus(.unavailable(reason: why))
                self.publish(nil)
            }
        }
    }

    private func publish(_ new: NowPlayingState?) {
        guard new != state else { return }
        state = new
        onState?(new)
    }

    private func setStatus(_ new: Status) {
        guard new != status else { return }
        status = new
        onStatus?(new)
    }
}
