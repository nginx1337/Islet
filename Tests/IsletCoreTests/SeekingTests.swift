import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

@Suite("Seek hold")
struct SeekHoldTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func state(elapsed: Double?, at date: Date? = nil, playing: Bool = true, title: String = "T",
               duration: Double? = 200) -> NowPlayingState {
        NowPlayingState(title: title, duration: duration, elapsed: elapsed, timestamp: date ?? t0,
                        rate: playing ? 1 : 0, isPlaying: playing)
    }

    @Test func showsTheTargetRightAway() {
        let hold = SeekHold(target: 120, state: state(elapsed: 30), at: t0)
        let shown = hold.applied(to: state(elapsed: 30), at: t0)
        #expect(PlaybackTimeline.position(of: shown, at: t0) == 120)
        #expect(PlaybackTimeline.position(of: shown, at: t0.addingTimeInterval(2)) == 122)
    }

    @Test func staleUpdateKeepsTheNewPosition() {
        var hold = SeekHold(target: 120, state: state(elapsed: 30), at: t0)
        // The player still reports the old spot half a second later (and new artwork, say).
        let now = t0.addingTimeInterval(0.5)
        let shown = hold.reconcile(state(elapsed: 30.5, at: now), at: now)
        #expect(!hold.isFinished)
        #expect(PlaybackTimeline.position(of: shown, at: now) == 120.5)
    }

    @Test func confirmationEndsTheHold() {
        var hold = SeekHold(target: 120, state: state(elapsed: 30), at: t0)
        let now = t0.addingTimeInterval(0.4)
        let incoming = state(elapsed: 120.2, at: now)
        let shown = hold.reconcile(incoming, at: now)
        #expect(hold.isFinished)
        #expect(shown == incoming)
        // Once finished, updates pass through untouched.
        let later = state(elapsed: 10, at: now)
        #expect(hold.reconcile(later, at: now) == later)
    }

    @Test func refusedSeekGivesWayAfterTheTimeout() {
        var hold = SeekHold(target: 120, state: state(elapsed: 30), at: t0)
        let now = t0.addingTimeInterval(SeekHold.timeout + 0.1)
        let incoming = state(elapsed: 33, at: now)
        #expect(hold.reconcile(incoming, at: now) == incoming)
        #expect(hold.isFinished)
    }

    @Test func anotherTrackEndsTheHold() {
        var hold = SeekHold(target: 120, state: state(elapsed: 30), at: t0)
        let incoming = state(elapsed: 0, title: "Next")
        #expect(hold.reconcile(incoming, at: t0.addingTimeInterval(0.2)) == incoming)
        #expect(hold.isFinished)
    }

    @Test func pauseWhileBufferingStopsTheCount() {
        var hold = SeekHold(target: 120, state: state(elapsed: 30), at: t0)
        // One second in, the player pauses (still reporting the old spot)…
        let paused = t0.addingTimeInterval(1)
        _ = hold.reconcile(state(elapsed: 30, at: paused, playing: false), at: paused)
        #expect(hold.expected(at: paused.addingTimeInterval(1)) == 121)
        // …and resumes: counting goes on from where it stopped.
        let resumed = paused.addingTimeInterval(1)
        _ = hold.reconcile(state(elapsed: 30, at: resumed), at: resumed)
        #expect(hold.expected(at: resumed.addingTimeInterval(0.5)) == 121.5)
    }

    @Test func updateWithoutPositionKeepsTheHold() {
        var hold = SeekHold(target: 60, state: state(elapsed: 10), at: t0)
        let now = t0.addingTimeInterval(0.25)
        let shown = hold.reconcile(state(elapsed: nil, at: now), at: now)
        #expect(!hold.isFinished)
        #expect(shown.elapsed == 60.25)
    }

    @Test func targetIsClampedToTheTrack() {
        #expect(SeekHold(target: 500, state: state(elapsed: 10), at: t0).expected(at: t0) == 200)
        #expect(SeekHold(target: -5, state: state(elapsed: 10), at: t0).expected(at: t0) == 0)
        #expect(SeekHold(target: .nan, state: state(elapsed: 10), at: t0).expected(at: t0) == 0)
        // Playing on never runs past the end.
        #expect(SeekHold(target: 199, state: state(elapsed: 10), at: t0).expected(at: t0.addingTimeInterval(5)) == 200)
    }
}

@Suite("Scrubber")
struct ScrubberTests {
    @Test func fractionUnderThePointer() {
        #expect(Scrubber.fraction(atX: 50, width: 200) == 0.25)
        #expect(Scrubber.fraction(atX: -30, width: 200) == 0)
        #expect(Scrubber.fraction(atX: 260, width: 200) == 1)
        #expect(Scrubber.fraction(atX: 10, width: 0) == 0)
        #expect(Scrubber.fraction(atX: .nan, width: 200) == 0)
    }

    @Test func overshootPastTheEnds() {
        #expect(Scrubber.overshoot(atX: 100, width: 200) == 0)
        #expect(Scrubber.overshoot(atX: -12, width: 200) == -12)
        #expect(Scrubber.overshoot(atX: 230, width: 200) == 30)
    }

    @Test func stretchIsARubberBand() {
        #expect(Scrubber.stretch(forOvershoot: 0) == 0)
        let small = Scrubber.stretch(forOvershoot: 10)
        let large = Scrubber.stretch(forOvershoot: 100)
        let huge = Scrubber.stretch(forOvershoot: 10_000)
        // Follows the pointer less than one to one, more the further it goes, never past the limit.
        #expect(small > 0 && small < 10)
        #expect(large > small)
        #expect(huge > large && huge < Scrubber.maxStretch)
        #expect(Scrubber.stretch(forOvershoot: -100) == -large)
        #expect(Scrubber.stretch(forOvershoot: .infinity) == 0)
        #expect(Scrubber.stretch(forOvershoot: 50, limit: 0) == 0)
    }
}
