import Foundation
import Testing
@testable import IsletCore

@MainActor
final class FakeSource: NowPlayingSource {
    let kind: SourceKind
    var handler: (@MainActor (NowPlayingSourceEvent) -> Void)?
    var startCount = 0
    var stopCount = 0
    var commands: [PlaybackCommand] = []
    /// What happens right when start() is called.
    var onStart: ((FakeSource) -> Void)?

    init(_ kind: SourceKind) { self.kind = kind }

    func start(_ onEvent: @escaping @MainActor (NowPlayingSourceEvent) -> Void) {
        startCount += 1
        handler = onEvent
        onStart?(self)
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func perform(_ command: PlaybackCommand) { commands.append(command) }

    func emit(_ event: NowPlayingSourceEvent) { handler?(event) }
}

@MainActor
@Suite("Source failover")
struct SourceSwitcherTests {
    let clock = ManualClock()
    let primary = FakeSource(.mediaRemote)
    let fallback = FakeSource(.musicSpotify)
    let song = NowPlayingState(bundleID: "com.apple.Music", title: "Song", isPlaying: true)

    func makeSwitcher() -> SourceSwitcher {
        SourceSwitcher(primary: primary, fallback: fallback, clock: clock)
    }

    @Test func healthyPrimaryStays() {
        let switcher = makeSwitcher()
        var states: [NowPlayingState?] = []
        switcher.onState = { states.append($0) }
        switcher.start()
        primary.emit(.started)
        primary.emit(.update(song))
        clock.advance(by: 30)
        #expect(switcher.status == .primary)
        #expect(switcher.activeKind == .mediaRemote)
        #expect(states == [song])
        #expect(fallback.startCount == 0)
        switcher.perform(.nextTrack)
        #expect(primary.commands == [.nextTrack])
    }

    @Test func primaryThatFailsToStartSwitchesImmediately() {
        primary.onStart = { $0.emit(.failed("perl exited with 1")) }
        let switcher = makeSwitcher()
        switcher.start()
        #expect(switcher.status == .fallback(reason: "perl exited with 1"))
        #expect(fallback.startCount == 1)
        #expect(primary.startCount == 1, "no restarts for a primary that never worked")
        fallback.emit(.update(song))
        #expect(switcher.state == song)
        switcher.perform(.togglePlayPause)
        #expect(fallback.commands == [.togglePlayPause])
        #expect(primary.commands.isEmpty)
    }

    @Test func silentPrimaryTimesOut() {
        let switcher = makeSwitcher()
        switcher.start()
        clock.advance(by: 4.9)
        #expect(switcher.status == .starting)
        clock.advance(by: 0.2)
        #expect(switcher.status == .fallback(reason: "timeout"))
        #expect(primary.stopCount == 1)
    }

    @Test func lateEventsFromAStoppedPrimaryAreIgnored() {
        let switcher = makeSwitcher()
        switcher.start()
        let stale = primary.handler
        clock.advance(by: 6)
        stale?(.update(song))
        #expect(switcher.state == nil)
    }

    @Test func crashAfterWorkingRestartsThenFallsBack() {
        let switcher = makeSwitcher()
        var statuses: [SourceSwitcher.Status] = []
        switcher.onStatus = { statuses.append($0) }
        switcher.start()
        primary.emit(.started)
        for _ in 0..<2 {
            primary.emit(.failed("crashed"))
            #expect(switcher.status == .starting)
            clock.advance(by: 1.1)
            primary.emit(.started)
            #expect(switcher.status == .primary)
        }
        #expect(primary.startCount == 3)
        primary.emit(.failed("crashed"))
        #expect(switcher.status == .fallback(reason: "crashed"), "restart budget used up")
        #expect(fallback.startCount == 1)
        #expect(statuses.last == .fallback(reason: "crashed"))
    }

    @Test func longHealthyRunEarnsRestartsBack() {
        let switcher = makeSwitcher()
        switcher.start()
        primary.emit(.started)
        for _ in 0..<5 {
            clock.advance(by: 120)
            primary.emit(.failed("crashed"))
            clock.advance(by: 1.1)
            primary.emit(.started)
        }
        #expect(switcher.status == .primary)
    }

    @Test func fallbackFailureMeansUnavailable() {
        primary.onStart = { $0.emit(.failed("blocked")) }
        let switcher = makeSwitcher()
        switcher.start()
        fallback.emit(.update(song))
        fallback.emit(.failed("no players"))
        #expect(switcher.status == .unavailable(reason: "no players"))
        #expect(switcher.state == nil)
    }

    @Test func retryPrimaryGoesBack() {
        primary.onStart = { $0.emit(.failed("blocked")) }
        let switcher = makeSwitcher()
        switcher.start()
        #expect(switcher.status.isFallback)
        primary.onStart = nil
        switcher.retryPrimary()
        primary.emit(.update(song))
        #expect(switcher.status == .primary)
        #expect(fallback.stopCount >= 1)
    }

    @Test func duplicateStatesAreNotRepublished() {
        let switcher = makeSwitcher()
        var count = 0
        switcher.onState = { _ in count += 1 }
        switcher.start()
        primary.emit(.update(song))
        primary.emit(.update(song))
        primary.emit(.update(nil))
        #expect(count == 2)
    }
}
