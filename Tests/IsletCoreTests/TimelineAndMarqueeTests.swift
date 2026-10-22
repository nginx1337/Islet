import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

@Suite("Position interpolation")
struct TimelineTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    func state(elapsed: Double, rate: Double = 1, playing: Bool = true, duration: Double? = 200) -> NowPlayingState {
        NowPlayingState(title: "T", duration: duration, elapsed: elapsed, timestamp: t0, rate: rate, isPlaying: playing)
    }

    @Test func movesWithTime() {
        #expect(PlaybackTimeline.position(of: state(elapsed: 10), at: t0.addingTimeInterval(5)) == 15)
    }

    @Test func respectsRate() {
        #expect(PlaybackTimeline.position(of: state(elapsed: 10, rate: 2), at: t0.addingTimeInterval(5)) == 20)
        #expect(PlaybackTimeline.position(of: state(elapsed: 10, rate: 0.5), at: t0.addingTimeInterval(4)) == 12)
    }

    @Test func pausedStandsStill() {
        #expect(PlaybackTimeline.position(of: state(elapsed: 10, playing: false), at: t0.addingTimeInterval(60)) == 10)
    }

    @Test func clampsToDurationAndZero() {
        #expect(PlaybackTimeline.position(of: state(elapsed: 190), at: t0.addingTimeInterval(60)) == 200)
        #expect(PlaybackTimeline.position(of: state(elapsed: 1, rate: -1), at: t0.addingTimeInterval(5)) == 0)
        #expect(PlaybackTimeline.position(of: state(elapsed: 50, duration: nil), at: t0.addingTimeInterval(1000)) == 1050)
    }

    @Test func missingTimestampUsesElapsedAsIs() {
        var s = state(elapsed: 33)
        s.timestamp = nil
        #expect(PlaybackTimeline.position(of: s, at: t0.addingTimeInterval(100)) == 33)
    }

    @Test func progress() {
        #expect(PlaybackTimeline.progress(of: state(elapsed: 50), at: t0) == 0.25)
        #expect(PlaybackTimeline.progress(of: state(elapsed: 50, duration: nil), at: t0) == nil)
    }

    @Test func formatting() {
        #expect(PlaybackTimeline.format(0) == "0:00")
        #expect(PlaybackTimeline.format(65.9) == "1:05")
        #expect(PlaybackTimeline.format(3723) == "1:02:03")
        #expect(PlaybackTimeline.format(-130) == "−2:10")
        #expect(PlaybackTimeline.format(.nan) == "–:––")
    }
}

@Suite("Marquee")
struct MarqueeTests {
    @Test func shortTextDoesNotMove() {
        let m = Marquee(textWidth: 100, containerWidth: 200)
        #expect(!m.isScrolling)
        #expect(m.offset(at: 10) == 0)
        #expect(m.cycleDuration == 0)
    }

    @Test func holdsThenScrollsAtConstantSpeed() {
        let m = Marquee(textWidth: 300, containerWidth: 200, speed: 30, gap: 30, pause: 2)
        #expect(m.isScrolling)
        #expect(m.offset(at: 1) == 0, "holding at the start")
        #expect(m.offset(at: 2) == 0)
        #expect(m.offset(at: 3) == -30)
        #expect(m.offset(at: 4) == -60)
    }

    @Test func loopsSeamlessly() {
        let m = Marquee(textWidth: 300, containerWidth: 200, speed: 30, gap: 30, pause: 2)
        #expect(m.travel == 330)
        #expect(m.cycleDuration == 13)
        // Right before the loop the second copy sits where the first started.
        #expect(abs(m.offset(at: 12.999) + 330) < 0.1)
        #expect(m.offset(at: 13.5) == 0, "next cycle starts with the hold")
        #expect(m.offset(at: 16) == -30)
    }

    @Test func neverMovesRight() {
        let m = Marquee(textWidth: 500, containerWidth: 120)
        for t in stride(from: 0.0, to: 60, by: 0.37) {
            let offset = m.offset(at: t)
            #expect(offset <= 0 && offset >= -m.travel)
        }
    }
}
