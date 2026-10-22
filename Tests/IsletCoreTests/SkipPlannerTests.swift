import Foundation
import Testing
@testable import IsletCore

@Suite("Back and forward buttons")
struct SkipPlannerTests {
    @Test func backRestartsAfterThreeSeconds() {
        #expect(SkipPlanner.back(position: 42, mode: .tracks) == .seek(0))
        #expect(SkipPlanner.back(position: 2, mode: .tracks) == .previousTrack)
    }

    @Test func secondsModeSkipsFifteen() {
        #expect(SkipPlanner.back(position: 42, mode: .seconds) == .seek(27))
        #expect(SkipPlanner.back(position: 5, mode: .seconds) == .seek(0))
        #expect(SkipPlanner.forward(position: 42, duration: 1258, mode: .seconds) == .seek(57))
        #expect(SkipPlanner.forward(position: 1250, duration: 1258, mode: .seconds) == .seek(1257.5))
        #expect(SkipPlanner.forward(position: 10, duration: nil, mode: .seconds) == .seek(25))
    }

    @Test func nextIsIgnoredOnlyWhenTheSameItemPlaysOn() {
        #expect(SkipPlanner.nextWasIgnored(sameTrack: true, isPlaying: true, positionBefore: 100, positionAfter: 103))
        #expect(!SkipPlanner.nextWasIgnored(sameTrack: false, isPlaying: true, positionBefore: 100, positionAfter: 1))
        #expect(!SkipPlanner.nextWasIgnored(sameTrack: true, isPlaying: true, positionBefore: 100, positionAfter: 100.4),
                "stalled: the next item is loading")
        #expect(!SkipPlanner.nextWasIgnored(sameTrack: true, isPlaying: false, positionBefore: 100, positionAfter: 103))
    }

    @Test func tracksModeSendsNext() {
        #expect(SkipPlanner.forward(position: 42, duration: 200, mode: .tracks) == .nextTrack)
    }
}
