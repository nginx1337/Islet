import Foundation
import Testing
@testable import IsletCore

@MainActor
@Suite("Island state machine")
struct StateMachineTests {
    let clock = ManualClock()

    func makeMachine(_ configure: (inout IslandBehavior) -> Void = { _ in }) -> IslandStateMachine {
        var behavior = IslandBehavior()
        configure(&behavior)
        return IslandStateMachine(clock: clock, behavior: behavior)
    }

    func track(_ title: String, playing: Bool = true) -> NowPlayingState {
        NowPlayingState(bundleID: "com.apple.Music", title: title, artist: "Artist", isPlaying: playing)
    }

    @Test func startsHiddenAndIdle() {
        let machine = makeMachine()
        #expect(machine.presentation == .hidden)
        #expect(machine.activeTimerCount == 0)
    }

    @Test func newTrackExpandsForThreeSecondsThenCompacts() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        #expect(machine.presentation == .expanded(.trackChange))
        clock.advance(by: 2.9)
        #expect(machine.presentation == .expanded(.trackChange))
        clock.advance(by: 0.2)
        #expect(machine.presentation == .compact(dimmed: false))
        #expect(machine.activeTimerCount == 0, "a steady playing island has no timers")
    }

    @Test func trackChangeExpansionCanBeTurnedOff() {
        let machine = makeMachine { $0.expandOnTrackChange = false }
        machine.mediaChanged(track("A"))
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func sameTrackUpdatesDoNotReExpand() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        var updated = track("A")
        updated.elapsed = 30
        machine.mediaChanged(updated)
        #expect(machine.presentation == .compact(dimmed: false))
        machine.mediaChanged(track("B"))
        #expect(machine.presentation == .expanded(.trackChange))
    }

    @Test func trackAnnouncedWhenItStartsPlayingAfterArrivingPaused() {
        let machine = makeMachine()
        machine.mediaChanged(track("A", playing: false))
        #expect(machine.presentation == .compact(dimmed: true))
        machine.mediaChanged(track("A", playing: true))
        #expect(machine.presentation == .expanded(.trackChange))
    }

    @Test func returningToATrackAfterAnotherItemAnnouncesItAgain() {
        // Seen on macOS 27: the player quits, a paused browser video becomes current,
        // then the player is reopened with the track it had before.
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        var video = track("Video", playing: false)
        video.bundleID = "com.apple.Safari"
        machine.mediaChanged(video)
        machine.mediaChanged(nil)
        machine.mediaChanged(track("A"))
        #expect(machine.presentation == .expanded(.trackChange))
    }

    @Test func pauseAndResumeOfTheSameTrackDoesNotReannounce() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.mediaChanged(track("A", playing: false))
        machine.mediaChanged(track("A"))
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func hoverExpandsAndLeavingCollapsesAfterDelay() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.pointerEntered()
        #expect(machine.presentation == .expanded(.hover))
        machine.pointerExited()
        clock.advance(by: 0.39)
        #expect(machine.presentation == .expanded(.hover))
        clock.advance(by: 0.02)
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func returningBeforeTheDelayKeepsItOpen() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.pointerEntered()
        machine.pointerExited()
        clock.advance(by: 0.2)
        machine.pointerEntered()
        clock.advance(by: 1)
        #expect(machine.presentation == .expanded(.hover))
    }

    @Test func hoverDuringTrackChangeTakesOver() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        machine.pointerEntered()
        #expect(machine.presentation == .expanded(.hover))
        clock.advance(by: 5)
        #expect(machine.presentation == .expanded(.hover), "the 3 s timer no longer closes it")
    }

    @Test func pointerStillInsideWhenTrackChangeEndsKeepsItOpen() {
        let machine = makeMachine { $0.expandOnHover = false }
        machine.mediaChanged(track("A"))
        machine.pointerEntered()
        #expect(machine.presentation == .expanded(.trackChange), "hover expansion is off")
        clock.advance(by: 3.1)
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func clickExpandsWhenHoverIsOff() {
        let machine = makeMachine { $0.expandOnHover = false }
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.pointerEntered()
        #expect(machine.presentation == .compact(dimmed: false))
        machine.clicked()
        #expect(machine.presentation == .expanded(.click))
        machine.pointerExited()
        clock.advance(by: 0.5)
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func clickWhileHiddenDoesNothing() {
        let machine = makeMachine()
        machine.clicked()
        #expect(machine.presentation == .hidden)
    }

    @Test func pauseDimsThenHidesAfterDelay() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.mediaChanged(track("A", playing: false))
        #expect(machine.presentation == .compact(dimmed: true))
        clock.advance(by: 14.9)
        #expect(machine.presentation == .compact(dimmed: true))
        clock.advance(by: 0.2)
        #expect(machine.presentation == .hidden)
        #expect(machine.activeTimerCount == 0, "a hidden island has no timers")
    }

    @Test func resumingCancelsThePauseTimer() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 10)
        machine.mediaChanged(track("A", playing: true))
        clock.advance(by: 10)
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func resumingAfterHiddenShowsAgainWithoutReannouncing() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 16)
        #expect(machine.presentation == .hidden)
        machine.mediaChanged(track("A", playing: true))
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func customPauseDelayAndNever() {
        let machine = makeMachine { $0.pauseHideDelay = 5 }
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 5.1)
        #expect(machine.presentation == .hidden)

        let keep = makeMachine { $0.pauseHideDelay = nil }
        keep.mediaChanged(track("A", playing: false))
        clock.advance(by: 3600)
        #expect(keep.presentation == .compact(dimmed: true))
        #expect(keep.activeTimerCount == 0)
    }

    @Test func pausedWhileHoveredHidesAfterLeaving() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.pointerEntered()
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 20)
        #expect(machine.presentation == .expanded(.hover), "stays open under the pointer")
        machine.pointerExited()
        clock.advance(by: 0.5)
        #expect(machine.presentation == .hidden)
    }

    @Test func nothingPlayingHidesAfterGrace() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        machine.mediaChanged(nil)
        #expect(machine.presentation == .expanded(.trackChange), "a short gap is ignored")
        clock.advance(by: 0.7)
        #expect(machine.presentation == .hidden)
        #expect(machine.media == nil)
        #expect(machine.activeTimerCount == 0)
    }

    @Test func playerSwitchGapDoesNotFlicker() {
        let machine = makeMachine()
        var changes: [IslandPresentation] = []
        machine.onChange = { _, new in changes.append(new) }
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.mediaChanged(nil)
        clock.advance(by: 0.3)
        var other = track("A")
        other.bundleID = "com.spotify.client"
        machine.mediaChanged(other)
        clock.advance(by: 1)
        #expect(!changes.contains(.hidden))
    }

    @Test func hotkeyTogglesAndAutoCloses() {
        let machine = makeMachine()
        machine.hotkeyPressed()
        #expect(machine.presentation == .hidden, "nothing to show")
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.hotkeyPressed()
        #expect(machine.presentation == .expanded(.hotkey))
        machine.hotkeyPressed()
        #expect(machine.presentation == .compact(dimmed: false))
        machine.hotkeyPressed()
        clock.advance(by: 5.1)
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func hotkeyShowsHiddenPausedMediaAndReturnsToHidden() {
        let machine = makeMachine()
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 16)
        #expect(machine.presentation == .hidden)
        machine.hotkeyPressed()
        #expect(machine.presentation == .expanded(.hotkey))
        clock.advance(by: 5.1)
        #expect(machine.presentation == .hidden)
    }

    @Test func hoverConvertsHotkeyExpansion() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.hotkeyPressed()
        machine.pointerEntered()
        #expect(machine.presentation == .expanded(.hover))
        clock.advance(by: 10)
        #expect(machine.presentation == .expanded(.hover))
    }

    @Test func hotkeyExpansionClosesWhenPointerLeavesWithHoverOff() {
        let machine = makeMachine { $0.expandOnHover = false }
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.hotkeyPressed()
        machine.pointerEntered()
        clock.advance(by: 6)
        #expect(machine.presentation == .expanded(.hotkey), "stays open under the pointer")
        machine.pointerExited()
        clock.advance(by: 0.5)
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func turningAutoHideOffShowsHiddenPausedMedia() {
        let machine = makeMachine()
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 16)
        #expect(machine.presentation == .hidden)
        machine.behavior.pauseHideDelay = nil
        #expect(machine.presentation == .compact(dimmed: true))
        #expect(machine.activeTimerCount == 0)
    }

    @Test func changingTheDelayWhilePausedUsesTheNewDelay() {
        let machine = makeMachine()
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 5)
        machine.behavior.pauseHideDelay = 60
        clock.advance(by: 15)
        #expect(machine.presentation == .compact(dimmed: true), "the old 15 s timer is gone")
        clock.advance(by: 46)
        #expect(machine.presentation == .hidden)
    }

    @Test func hoverOnHiddenIslandIsIgnored() {
        let machine = makeMachine()
        machine.pointerEntered()
        #expect(machine.presentation == .hidden)
    }

    @Test func collapseClosesImmediately() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        machine.collapse()
        #expect(machine.presentation == .compact(dimmed: false))
        #expect(machine.activeTimerCount == 0)
    }

    @Test func reportsEveryTransition() {
        let machine = makeMachine()
        var log: [String] = []
        machine.onChange = { old, new in log.append("\(old)→\(new)") }
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.mediaChanged(track("A", playing: false))
        clock.advance(by: 15.1)
        #expect(log == [
            "hidden→expanded(IsletCore.ExpandReason.trackChange)",
            "expanded(IsletCore.ExpandReason.trackChange)→compact(dimmed: false)",
            "compact(dimmed: false)→compact(dimmed: true)",
            "compact(dimmed: true)→hidden"
        ])
    }

    // MARK: Hidden by the user

    @Test func suppressingHidesAndShowingBringsItBack() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        clock.advance(by: 3.1)
        machine.isSuppressed = true
        #expect(machine.presentation == .hidden)
        #expect(machine.activeTimerCount == 0)
        machine.isSuppressed = false
        #expect(machine.presentation == .compact(dimmed: false))
    }

    @Test func suppressingClosesAnExpandedIsland() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        machine.pointerEntered()
        #expect(machine.presentation.isExpanded)
        machine.isSuppressed = true
        #expect(machine.presentation == .hidden)
        machine.pointerExited()
        machine.isSuppressed = false
        #expect(machine.presentation == .compact(dimmed: false), "comes back compact, not expanded")
    }

    @Test func suppressedIslandIgnoresNewTracksHoverAndHotkey() {
        let machine = makeMachine()
        machine.mediaChanged(track("A"))
        machine.isSuppressed = true
        machine.mediaChanged(track("B"))
        #expect(machine.presentation == .hidden)
        machine.pointerEntered()
        machine.clicked()
        machine.hotkeyPressed()
        #expect(machine.presentation == .hidden)
        machine.pointerExited()
        clock.advance(by: 10)
        machine.isSuppressed = false
        #expect(machine.presentation == .compact(dimmed: false), "B is not announced afterwards")
    }

    @Test func pausedMediaStillHidesAfterShowingAgain() {
        let machine = makeMachine { $0.pauseHideDelay = 15 }
        machine.mediaChanged(track("A", playing: false))
        machine.isSuppressed = true
        clock.advance(by: 20)
        machine.isSuppressed = false
        #expect(machine.presentation == .hidden, "the pause delay ran out meanwhile")
    }
}

