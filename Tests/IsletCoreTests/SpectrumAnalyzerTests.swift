import Foundation
import Testing
@testable import IsletCore

@Suite("Equaliser bars from real audio")
struct SpectrumAnalyzerTests {
    static let rate = 48_000.0

    static func tone(_ frequencies: [Double], amplitude: Float = 0.4, seconds: Double = 0.6) -> [Float] {
        let count = Int(rate * seconds)
        return (0..<count).map { i in
            let t = Double(i) / rate
            return frequencies.reduce(Float(0)) { $0 + amplitude * Float(sin(2 * .pi * $1 * t)) } / Float(frequencies.count)
        }
    }

    @Test func bassToneLiftsTheBassBar() {
        let analyzer = SpectrumAnalyzer(sampleRate: Self.rate)
        analyzer.process(Self.tone([70]))
        #expect(analyzer.levels[0] > 0.8)
        #expect(analyzer.levels[2] < 0.2 && analyzer.levels[3] < 0.2)
        #expect(analyzer.signalSeen)
    }

    @Test func highToneLiftsTheTopBar() {
        let analyzer = SpectrumAnalyzer(sampleRate: Self.rate)
        analyzer.process(Self.tone([5000]))
        #expect(analyzer.levels[3] > 0.8)
        #expect(analyzer.levels[0] < 0.2)
    }

    @Test func midToneLiftsTheMidBar() {
        let analyzer = SpectrumAnalyzer(sampleRate: Self.rate)
        analyzer.process(Self.tone([1200]))
        #expect(analyzer.levels[2] > 0.8)
        #expect(analyzer.levels[0] < 0.2)
    }

    @Test func silenceDropsTheBars() {
        let analyzer = SpectrumAnalyzer(sampleRate: Self.rate)
        analyzer.process(Self.tone([70, 1200]))
        #expect(analyzer.levels[0] > 0.5)
        analyzer.process([Float](repeating: 0, count: 48_000 / 2))
        #expect(!analyzer.hasSignal)
        #expect(analyzer.levels.allSatisfy { $0 < 0.05 })
    }

    @Test func allZeroInputMeansNoAccess() {
        let analyzer = SpectrumAnalyzer(sampleRate: Self.rate)
        analyzer.process([Float](repeating: 0, count: 48_000))
        #expect(!analyzer.signalSeen)
        #expect(analyzer.levels == [0, 0, 0, 0])
    }

    @Test func quietMusicStillMovesTheBars() {
        // The reference adapts: a quiet passage after a while reaches the same height.
        let analyzer = SpectrumAnalyzer(sampleRate: Self.rate)
        analyzer.process(Self.tone([70], amplitude: 0.02, seconds: 1.5))
        #expect(analyzer.levels[0] > 0.8)
    }

    @Test func updatesEveryHop() {
        let analyzer = SpectrumAnalyzer(sampleRate: Self.rate)
        #expect(!analyzer.process([Float](repeating: 0.1, count: 511)))
        #expect(analyzer.process([Float](repeating: 0.1, count: 1)))
    }
}
