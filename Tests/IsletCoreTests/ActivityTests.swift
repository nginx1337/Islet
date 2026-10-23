import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

@MainActor
struct ActivityCenterTests {
    let clock = ManualClock()
    let center: ActivityCenter

    init() {
        center = ActivityCenter(clock: clock)
    }

    @Test func emptyCentreHasNothingScheduled() {
        #expect(center.current == nil)
        #expect(clock.pendingCount == 0)
    }

    @Test func timerCountsDownAndFinishes() {
        var finished = 0
        center.onTimerFinished = { finished += 1 }
        center.startTimer(duration: 60)
        guard case .countdown(let timer) = center.current?.content else { return Issue.record("no timer") }
        #expect(timer.remaining(at: clock.now) == 60)
        clock.advance(by: 30)
        #expect(finished == 0)
        clock.advance(by: 30.1)
        #expect(finished == 1)
        guard case .countdown(let done) = center.current?.content else { return Issue.record("timer gone too early") }
        #expect(done.isFinished)
    }

    @Test func finishedTimerRingsThenDisappears() {
        center.startTimer(duration: 5)
        clock.advance(by: 5.1)
        #expect(center.current != nil)
        clock.advance(by: ActivityCenter.finishedDuration + 0.1)
        #expect(center.current == nil)
        #expect(clock.pendingCount == 0, "nothing stays scheduled")
    }

    @Test func pausedTimerKeepsItsRemainingTime() {
        center.startTimer(duration: 100)
        clock.advance(by: 40)
        center.toggleTimer()
        clock.advance(by: 500)
        guard case .countdown(let timer) = center.current?.content else { return Issue.record("no timer") }
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: clock.now) == 60)
        #expect(clock.pendingCount == 0, "a paused timer has no deadline")
        center.toggleTimer()
        clock.advance(by: 59)
        guard case .countdown(let resumed) = center.current?.content else { return Issue.record("no timer") }
        #expect(resumed.isRunning)
        clock.advance(by: 1.1)
        guard case .countdown(let done) = center.current?.content else { return Issue.record("no timer") }
        #expect(done.isFinished)
    }

    @Test func togglingAFinishedTimerDismissesIt() {
        center.startTimer(duration: 2)
        clock.advance(by: 2.5)
        center.toggleTimer()
        #expect(center.activity(.timer) == nil)
    }

    @Test func noticesExpireByThemselves() {
        center.postNotice(.power(PowerInfo(event: .pluggedIn, percent: 80)))
        #expect(center.current != nil)
        clock.advance(by: ActivityCenter.noticeDuration + 0.1)
        #expect(center.current == nil)
    }

    @Test func importantActivitiesWinTheCapsule() {
        center.update(.transfer(TransferInfo(operation: .copy, fraction: 0.2)))
        #expect(center.current?.kind == .transfer)
        center.startStopwatch()
        #expect(center.current?.kind == .stopwatch)
        center.startTimer(duration: 100)
        #expect(center.current?.kind == .timer)
        center.postNotice(.power(PowerInfo(event: .unplugged, percent: 50)))
        #expect(center.current?.kind == .power)
        #expect(center.activities.count == 4)
        clock.advance(by: ActivityCenter.noticeDuration + 0.1)
        #expect(center.current?.kind == .timer)
    }

    @Test func finishedTimerOutranksEverything() {
        center.startTimer(duration: 1)
        center.postNotice(.headphones(name: "AirPods"))
        clock.advance(by: 1.5)
        #expect(center.current?.kind == .timer)
    }

    @Test func unchangedTransferUpdateIsIgnored() {
        var changes = 0
        center.onChange = { changes += 1 }
        let info = ActivityContent.transfer(TransferInfo(operation: .download, fraction: 0.5))
        center.update(info)
        center.update(info)
        #expect(changes == 1)
        center.remove(.transfer)
        #expect(changes == 2)
        center.remove(.transfer)
        #expect(changes == 2)
    }

    @Test func stopwatchRunsPausesAndResumes() {
        center.startStopwatch()
        clock.advance(by: 10)
        center.toggleStopwatch()
        clock.advance(by: 100)
        guard case .stopwatch(let paused) = center.current?.content else { return Issue.record("no stopwatch") }
        #expect(paused.elapsed(at: clock.now) == 10)
        center.toggleStopwatch()
        clock.advance(by: 5)
        guard case .stopwatch(let running) = center.current?.content else { return Issue.record("no stopwatch") }
        #expect(running.elapsed(at: clock.now) == 15)
        #expect(clock.pendingCount == 0, "a stopwatch needs no timers")
    }
}

struct ActivityValueTests {
    @Test func timerDurationIsClamped() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(CountdownTimer(duration: -5, startingAt: now).total == CountdownTimer.minDuration)
        #expect(CountdownTimer(duration: 1e12, startingAt: now).total == CountdownTimer.maxDuration)
        #expect(CountdownTimer(duration: .nan, startingAt: now).total == 60)
        #expect(CountdownTimer(duration: .infinity, startingAt: now).total == 60)
    }

    @Test func timerKnowsWhenItHasEnded() {
        let start = Date(timeIntervalSince1970: 0)
        var timer = CountdownTimer(duration: 10, startingAt: start)
        #expect(!timer.hasEnded(at: start.addingTimeInterval(9.9)))
        #expect(timer.hasEnded(at: start.addingTimeInterval(10)))
        #expect(timer.remaining(at: start.addingTimeInterval(99)) == 0)
        #expect(timer.fractionLeft(at: start.addingTimeInterval(5)) == 0.5)
        timer.pause(at: start.addingTimeInterval(4))
        #expect(!timer.hasEnded(at: start.addingTimeInterval(99)), "a paused timer never ends")
        timer.finish()
        #expect(timer.isFinished && !timer.isRunning)
    }

    @Test func infoValuesAreClamped() {
        #expect(PowerInfo(event: .low, percent: 250).percent == 100)
        #expect(PowerInfo(event: .low, percent: -3).percent == 0)
        #expect(TransferInfo(operation: .copy, fraction: 7).fraction == 1)
        #expect(TransferInfo(operation: .copy, fraction: .nan).fraction == nil)
    }

    @Test func clockFormat() {
        #expect(TimeFormat.clock(0) == "0:00")
        #expect(TimeFormat.clock(-4) == "0:00")
        #expect(TimeFormat.clock(.nan) == "0:00")
        #expect(TimeFormat.clock(59) == "0:59")
        #expect(TimeFormat.clock(61) == "1:01")
        #expect(TimeFormat.clock(3723) == "1:02:03")
        #expect(TimeFormat.clock(59.2, roundingUp: true) == "1:00")
        #expect(TimeFormat.clock(59.2) == "0:59")
    }

    @Test func displayNamesAreCutAndCleaned() {
        #expect(TimeFormat.displayName("AirPods") == "AirPods")
        #expect(TimeFormat.displayName("a\nb\u{7}c") == "abc")
        let cut = TimeFormat.displayName(String(repeating: "x", count: 100), limit: 10)
        #expect(cut.count == 10)
        #expect(cut.hasSuffix("…"))
    }
}

struct SatelliteGeometryTests {
    static let macBook = ScreenDescriptor(
        id: "mb", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), backingScale: 2, safeAreaTop: 32,
        auxiliaryLeftWidth: 662, auxiliaryRightWidth: 662, isBuiltIn: true, isMain: true)
    static let monitor = ScreenDescriptor(
        id: "m", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), backingScale: 1,
        isMain: true, statusBarThickness: 24, visibleTopInset: 30)

    @Test func capsuleFitsInThePanelInEveryState() {
        for screen in [Self.macBook, Self.monitor] {
            for scale in [0.7, 1.0, 1.5] {
                let settings = LayoutSettings(notchScale: scale, islandScale: scale, compactTitle: true)
                let layout = IslandLayoutEngine.layout(for: screen, settings: settings)
                let bounds = CGRect(origin: .zero, size: layout.panelFrame.size)
                let width = SatellitePlacement.width(for: .countdown(CountdownTimer(duration: 5, startingAt: Date())), scale: layout.scale)
                for shape in [layout.hidden, layout.compact, layout.expanded] {
                    let frame = SatellitePlacement.frame(in: layout, main: shape, mainHidden: shape == layout.hidden, width: width)
                    #expect(bounds.contains(frame), "\(screen.id) scale \(scale)")
                    #expect(frame.height == layout.compact.frame.height)
                    #expect(frame.minY == layout.compact.frame.minY)
                }
            }
        }
    }

    @Test func capsuleIsOnTheRightAndDoesNotOverlapTheIsland() {
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        for shape in [layout.compact, layout.expanded] {
            let frame = SatellitePlacement.frame(in: layout, main: shape, mainHidden: false, width: 90)
            #expect(frame.minX >= shape.hitRect.maxX + SatellitePlacement.gap - 0.001)
        }
    }

    @Test func monitorCapsuleIsCentredWhenTheIslandIsHidden() {
        let layout = IslandLayoutEngine.layout(for: Self.monitor, settings: LayoutSettings())
        let alone = SatellitePlacement.frame(in: layout, main: layout.hidden, mainHidden: true, width: 90)
        #expect(alone.midX == layout.compact.frame.midX)
        let notch = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        let beside = SatellitePlacement.frame(in: notch, main: notch.hidden, mainHidden: true, width: 90)
        #expect(beside.minX > notch.hidden.frame.maxX, "stays beside the notch")
    }

    @Test func panelStaysCentredWithTheReserve() {
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        #expect(layout.panelFrame.midX == 756)
        let wide = IslandLayoutEngine.layout(for: Self.monitor, settings: LayoutSettings())
        #expect(wide.panelFrame.midX == Self.monitor.frame.midX)
    }
}
