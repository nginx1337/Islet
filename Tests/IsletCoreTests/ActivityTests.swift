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
        guard case .countdown(let timer) = center.current?.content else { Issue.record("no timer"); return }
        #expect(timer.remaining(at: clock.now) == 60)
        clock.advance(by: 30)
        #expect(finished == 0)
        clock.advance(by: 30.1)
        #expect(finished == 1)
        guard case .countdown(let done) = center.current?.content else { Issue.record("timer gone too early"); return }
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
        guard case .countdown(let timer) = center.current?.content else { Issue.record("no timer"); return }
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: clock.now) == 60)
        #expect(clock.pendingCount == 0, "a paused timer has no deadline")
        center.toggleTimer()
        clock.advance(by: 59)
        guard case .countdown(let resumed) = center.current?.content else { Issue.record("no timer"); return }
        #expect(resumed.isRunning)
        clock.advance(by: 1.1)
        guard case .countdown(let done) = center.current?.content else { Issue.record("no timer"); return }
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
        clock.advance(by: ActivityCenter.defaultNoticeDuration + 0.1)
        #expect(center.current == nil)
    }

    @Test func noticeDurationIsAdjustableWithinLimits() {
        center.noticeDuration = 7
        center.postNotice(.headphones(name: "AirPods"))
        clock.advance(by: 6.9)
        #expect(center.current?.kind == .headphones)
        clock.advance(by: 0.2)
        #expect(center.current == nil)
        center.noticeDuration = 100
        #expect(center.noticeDuration == ActivityCenter.noticeDurationRange.upperBound)
        center.noticeDuration = 0
        #expect(center.noticeDuration == ActivityCenter.noticeDurationRange.lowerBound)
        center.noticeDuration = .nan
        #expect(center.noticeDuration == ActivityCenter.defaultNoticeDuration)
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
        clock.advance(by: ActivityCenter.defaultNoticeDuration + 0.1)
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
        guard case .stopwatch(let paused) = center.current?.content else { Issue.record("no stopwatch"); return }
        #expect(paused.elapsed(at: clock.now) == 10)
        center.toggleStopwatch()
        clock.advance(by: 5)
        guard case .stopwatch(let running) = center.current?.content else { Issue.record("no stopwatch"); return }
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

    static let timer = ActivityContent.countdown(CountdownTimer(duration: 300, startingAt: Date()))
    static let headphones = ActivityContent.headphones(name: "AirPods Pro")
    static let allModes: [SatelliteMode] = [.bubble, .island, .expanded, .notice]

    // MARK: Modes

    @Test func modesFollowTheDynamicIsland() {
        #expect(SatellitePlacement.mode(for: Self.timer, main: .compact, expanded: false) == .bubble)
        #expect(SatellitePlacement.mode(for: Self.timer, main: .expanded, expanded: false) == .bubble)
        #expect(SatellitePlacement.mode(for: Self.timer, main: .hidden, expanded: false) == .island)
        #expect(SatellitePlacement.mode(for: Self.timer, main: .compact, expanded: true) == .expanded)
        #expect(SatellitePlacement.mode(for: Self.timer, main: .hidden, expanded: true) == .expanded)
        #expect(SatellitePlacement.mode(for: Self.headphones, main: .compact, expanded: false) == .notice)
        #expect(SatellitePlacement.mode(for: .power(PowerInfo(event: .pluggedIn, percent: 50)), main: .hidden, expanded: false) == .notice)
    }

    @Test func noticesNeverCoverTheExpandedIslandAndDoNotOpen() {
        #expect(SatellitePlacement.mode(for: Self.headphones, main: .expanded, expanded: false) == .bubble)
        #expect(SatellitePlacement.mode(for: Self.headphones, main: .expanded, expanded: true) == .bubble)
        #expect(SatellitePlacement.mode(for: Self.headphones, main: .compact, expanded: true) == .notice)
    }

    // MARK: Frames

    @Test func everyModeFitsInThePanel() {
        for screen in [Self.macBook, Self.monitor] {
            for scale in [0.7, 1.0, 1.5] {
                for preference in IslandStylePreference.allCases {
                    let settings = LayoutSettings(
                        notchScale: scale, islandScale: scale, compactTitle: true, stylePreference: preference)
                    let layout = IslandLayoutEngine.layout(for: screen, settings: settings)
                    let bounds = CGRect(origin: .zero, size: layout.panelFrame.size)
                    for shape in [layout.hidden, layout.compact, layout.expanded] {
                        for mode in Self.allModes {
                            let frame = SatellitePlacement.frame(in: layout, main: shape, mode: mode)
                            #expect(bounds.contains(frame), "\(screen.id) \(preference) \(mode) scale \(scale)")
                            #expect(frame.minY == layout.compact.frame.minY, "hangs from the island's top")
                        }
                    }
                }
            }
        }
    }

    @Test func bubbleIsACircleOnTheRightOfTheIsland() {
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        for shape in [layout.compact, layout.expanded] {
            let bubble = SatellitePlacement.frame(in: layout, main: shape, mode: .bubble)
            #expect(bubble.width == bubble.height)
            #expect(bubble.height == layout.compact.frame.height)
            #expect(bubble.minX >= shape.hitRect.maxX + SatellitePlacement.gap - 0.001)
            #expect(bubble.minX - shape.frame.maxX == SatellitePlacement.bubbleOffset(from: shape))
        }
    }

    @Test func islandModeSitsOnTheNotchWithRoomOnBothSides() {
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        #expect(SatellitePlacement.hasPhysicalNotch(layout))
        let island = SatellitePlacement.frame(in: layout, main: layout.hidden, mode: .island)
        #expect(island.midX == layout.compact.frame.midX)
        #expect(island.height == layout.compact.frame.height)
        #expect((island.width - layout.notchWidth) / 2 >= SatellitePlacement.islandEar, "each side holds a glyph or the time")
    }

    @Test func notchSidesNeverShrinkBelowTheirContent() {
        // The notch keeps its height at every size, and so does the time drawn from it.
        let small = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings(notchScale: 0.7))
        let normal = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        let a = SatellitePlacement.frame(in: small, main: small.hidden, mode: .island)
        let b = SatellitePlacement.frame(in: normal, main: normal.hidden, mode: .island)
        #expect(a.width >= b.width)
    }

    @Test func cardsHangBelowTheMenuBarAndCoverTheIsland() {
        for screen in [Self.macBook, Self.monitor] {
            for scale in [0.7, 1.0, 1.5] {
                let layout = IslandLayoutEngine.layout(
                    for: screen, settings: LayoutSettings(notchScale: scale, islandScale: scale, compactTitle: true))
                let widest = layout.compact(fittingTitle: 2000)
                let card = SatellitePlacement.frame(in: layout, main: widest, mode: .expanded)
                #expect(card.minX <= widest.frame.minX && card.maxX >= widest.frame.maxX, "\(screen.id) \(scale)")
                #expect(abs(card.midX - layout.compact.frame.midX) <= 0.5, "centred on the island (to the pixel)")
                #expect(card.height > layout.contentTopInset + 40 * layout.scale, "room for content below the menu bar")
                #expect(card.height < layout.expanded.frame.height, "smaller than the expanded music island")
                #expect(card.width == layout.expanded.frame.width)
            }
        }
    }

    @Test func noticeIsNarrowerThanTheExpandedIsland() {
        let layout = IslandLayoutEngine.layout(for: Self.monitor, settings: LayoutSettings())
        let notice = SatellitePlacement.frame(in: layout, main: layout.compact, mode: .notice)
        #expect(notice.width < layout.expanded.frame.width)
        #expect(notice.width == SatellitePlacement.noticeWidth)
    }

    @Test func noticeIsTheIslandStretchedSideways() {
        for screen in [Self.macBook, Self.monitor] {
            for scale in [0.7, 1.0, 1.5] {
                for title in [false, true] {
                    let layout = IslandLayoutEngine.layout(
                        for: screen, settings: LayoutSettings(notchScale: scale, islandScale: scale, compactTitle: title))
                    for main in [layout.hidden, layout.compact(fittingTitle: 2000)] {
                        let notice = SatellitePlacement.frame(in: layout, main: main, mode: .notice)
                        let label = "\(screen.id) \(scale) \(title)"
                        #expect(notice.minY == layout.compact.frame.minY, "\(label)")
                        #expect(notice.height == layout.compact.frame.height, "as tall as the island: \(label)")
                        #expect(abs(notice.midX - layout.compact.frame.midX) <= 0.5, "centred on it: \(label)")
                        #expect(notice.width > layout.compactBaseWidth, "wider than the island at rest: \(label)")
                        if main.opacity > 0 {
                            // Comes out of the island on both sides, so the stretch is always visible.
                            let growth = (SatellitePlacement.noticeGrowth * SatellitePlacement.contentScale(layout)).rounded()
                            #expect(notice.minX <= main.frame.minX - growth + 0.5, "past its left end: \(label)")
                            #expect(notice.maxX >= main.frame.maxX + growth - 0.5, "past its right end: \(label)")
                        }
                    }
                }
            }
        }
    }

    @Test func noticeKeepsEachSideBesideTheNotch() {
        for scale in [0.7, 1.0, 1.5] {
            let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings(notchScale: scale))
            #expect(SatellitePlacement.hasPhysicalNotch(layout))
            let notice = SatellitePlacement.frame(in: layout, main: layout.compact, mode: .notice)
            // "Low battery" on the left, the charge and the battery on the right, at every size.
            #expect((notice.width - layout.notchWidth) / 2 >= SatellitePlacement.noticeEar, "scale \(scale)")
        }
    }

    @Test func shapesMatchTheIslandTheyStandFor() {
        let notch = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        let pill = IslandLayoutEngine.layout(for: Self.monitor, settings: LayoutSettings())
        for layout in [notch, pill] {
            let bubble = SatellitePlacement.frame(in: layout, main: layout.compact, mode: .bubble)
            let circle = SatellitePlacement.shape(of: bubble, mode: .bubble, in: layout)
            #expect(circle.cornerRadius == bubble.height / 2 && circle.topFlare == 0, "a bubble is always a circle")
            #expect(!circle.contains(CGPoint(x: bubble.minX + 1, y: bubble.minY + 1)), "its empty corners take no clicks")
            #expect(circle.contains(CGPoint(x: bubble.midX, y: bubble.midY)))
            let card = SatellitePlacement.frame(in: layout, main: layout.compact, mode: .expanded)
            let spec = SatellitePlacement.shape(of: card, mode: .expanded, in: layout)
            #expect(spec.cornerRadius == layout.expanded.cornerRadius, "cards are rounded like the expanded island")
            #expect(spec.topFlare == layout.expanded.topFlare, "and hang from the top edge in the notch look")
            // A notice is the island itself, stretched: its ends and its flares are the island's.
            let notice = SatellitePlacement.frame(in: layout, main: layout.compact, mode: .notice)
            #expect(SatellitePlacement.shape(of: notice, mode: .notice, in: layout) == layout.compact.withFrame(notice))
        }
        let island = SatellitePlacement.frame(in: notch, main: notch.hidden, mode: .island)
        #expect(SatellitePlacement.shape(of: island, mode: .island, in: notch) == notch.compact.withFrame(island))
    }

    @Test func controlsBelongToTimersAndStopwatches() {
        #expect(Self.timer.hasControls)
        #expect(ActivityContent.stopwatch(Stopwatch(startingAt: Date())).hasControls)
        #expect(!Self.headphones.hasControls)
        var finished = CountdownTimer(duration: 5, startingAt: Date())
        finished.finish()
        #expect(!ActivityContent.countdown(finished).hasControls)
    }

    @Test func panelStaysCentredWithTheReserve() {
        let layout = IslandLayoutEngine.layout(for: Self.macBook, settings: LayoutSettings())
        #expect(layout.panelFrame.midX == 756)
        let wide = IslandLayoutEngine.layout(for: Self.monitor, settings: LayoutSettings())
        #expect(wide.panelFrame.midX == Self.monitor.frame.midX)
    }

    // MARK: Device glyphs

    @Test func deviceGlyphFollowsTheName() {
        #expect(DeviceGlyph.symbol(forDeviceName: "AirPods Pro Ивана") == "airpodspro")
        #expect(DeviceGlyph.symbol(forDeviceName: "Ivan’s AirPods Max") == "airpodsmax")
        #expect(DeviceGlyph.symbol(forDeviceName: "AirPods") == "airpods")
        #expect(DeviceGlyph.symbol(forDeviceName: "Beats Studio Pro") == "beats.headphones")
        #expect(DeviceGlyph.symbol(forDeviceName: "HomePod mini") == "homepod.fill")
        #expect(DeviceGlyph.symbol(forDeviceName: "JBL Flip 6") == "hifispeaker.fill")
        #expect(DeviceGlyph.symbol(forDeviceName: "Колонка на кухне") == "hifispeaker.fill")
        #expect(DeviceGlyph.symbol(forDeviceName: "WH-1000XM5") == "headphones")
        #expect(DeviceGlyph.symbol(forDeviceName: "") == "headphones")
    }
}

private extension ShapeSpec {
    func withFrame(_ frame: CGRect) -> ShapeSpec {
        var copy = self
        copy.frame = frame
        return copy
    }
}
