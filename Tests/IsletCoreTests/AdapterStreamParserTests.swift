import Foundation
import Testing
@testable import IsletCore

@Suite("Adapter JSON stream")
struct AdapterStreamParserTests {
    /// Real lines captured from the adapter on macOS 27 (artwork shortened).
    static let safariLine = #"{"type":"data","diff":false,"payload":{"playbackRate":1,"timestampEpochMicros":1792665500500802,"album":"","elapsedTimeMicros":3557499936,"playing":true,"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","processIdentifier":757,"title":"Угадай Рэпера!","uniqueIdentifier":12673137,"artist":"ExileShow","contentItemIdentifier":"12673137","durationMicros":4694261000}}"#

    @Test func parsesFullPayload() throws {
        let parser = AdapterStreamParser()
        let outputs = parser.feed(Self.safariLine + "\n")
        #expect(outputs.count == 1)
        guard case .update(let state?) = outputs.first else {
            Issue.record("expected a state")
            return
        }
        #expect(state.title == "Угадай Рэпера!")
        #expect(state.artist == "ExileShow")
        #expect(state.bundleID == "com.apple.Safari", "the browser, not its WebKit helper")
        #expect(state.isPlaying)
        #expect(state.rate == 1)
        #expect(abs((state.duration ?? 0) - 4694.261) < 0.0001)
        #expect(abs((state.elapsed ?? 0) - 3557.499936) < 0.0001)
        #expect(abs(state.timestamp!.timeIntervalSince1970 - 1792665500.500802) < 0.0001)
    }

    @Test func mergesDiffsAndRemovesNullKeys() {
        let parser = AdapterStreamParser()
        _ = parser.feed(Self.safariLine + "\n")
        let paused = parser.feed(#"{"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0}}"# + "\n")
        guard case .update(let state?) = paused.first else {
            Issue.record("expected a state")
            return
        }
        #expect(!state.isPlaying)
        #expect(state.title == "Угадай Рэпера!", "untouched keys are kept")

        let cleared = parser.feed(#"{"type":"data","diff":true,"payload":{"artist":null}}"# + "\n")
        guard case .update(let after?) = cleared.first else {
            Issue.record("expected a state")
            return
        }
        #expect(after.artist == "")
    }

    @Test func artworkArrivesInALaterDiff() {
        let parser = AdapterStreamParser()
        _ = parser.feed(#"{"type":"data","diff":false,"payload":{"title":"A","playing":true,"bundleIdentifier":"x"}}"# + "\n")
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let line = #"{"type":"data","diff":true,"payload":{"artworkMimeType":"image/png","artworkData":"\#(png.base64EncodedString())"}}"#
        guard case .update(let state?) = parser.feed(line + "\n").first else {
            Issue.record("expected a state")
            return
        }
        #expect(state.artworkData == png)
        #expect(state.artworkKey != nil)
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        let parser = AdapterStreamParser()
        #expect(parser.feed(#"{"type":"data","diff":false,"payload":{}}"# + "\n") == [.update(nil)])
        _ = parser.feed(Self.safariLine + "\n")
        #expect(parser.currentState != nil)
        #expect(parser.feed(#"{"type":"data","diff":false,"payload":{}}"# + "\n") == [.update(nil)])
    }

    @Test func emptyInputProducesNothing() {
        let parser = AdapterStreamParser()
        #expect(parser.feed("").isEmpty)
        #expect(parser.feed("\n\n  \n").isEmpty)
        #expect(parser.currentState == nil)
    }

    @Test func brokenLinesAreSkippedAndStateKept() {
        let parser = AdapterStreamParser()
        _ = parser.feed(Self.safariLine + "\n")
        let outputs = parser.feed("{not json\n" + #"{"payload":{}}"# + "\n" + #"{"type":"data","payload":5}"# + "\n")
        #expect(outputs == [.malformed, .malformed, .malformed])
        #expect(parser.malformedLines == 3)
        #expect(parser.currentState?.title == "Угадай Рэпера!")
    }

    @Test func otherMessageTypesAreIgnored() {
        let parser = AdapterStreamParser()
        #expect(parser.feed(#"{"type":"log","payload":{"title":"x"}}"# + "\n") == [.ignored])
    }

    @Test func linesSplitAcrossChunks() {
        let parser = AdapterStreamParser()
        let bytes = Data((Self.safariLine + "\n" + #"{"type":"data","diff":true,"payload":{"playing":false}}"# + "\n").utf8)
        var outputs: [AdapterStreamParser.Output] = []
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let end = min(index + 7, bytes.endIndex)
            outputs += parser.feed(bytes[index..<end])
            index = end
        }
        #expect(outputs.count == 2)
        #expect(parser.currentState?.isPlaying == false)
    }

    @Test func missingTitleIsNotMedia() {
        let parser = AdapterStreamParser()
        #expect(parser.feed(#"{"type":"data","diff":false,"payload":{"playing":true,"title":""}}"# + "\n") == [.update(nil)])
    }

    @Test func secondsFormatAndIsoTimestampAreAccepted() {
        let state = AdapterStreamParser.state(from: [
            "title": "T", "playing": false, "duration": 200, "elapsedTime": 42.5,
            "timestamp": "2026-10-22T10:38:05Z", "bundleIdentifier": "dev.spike.FakePlayer"
        ])
        #expect(state?.duration == 200)
        #expect(state?.elapsed == 42.5)
        #expect(state?.rate == 0, "a paused item without playbackRate does not move")
        #expect(state?.timestamp != nil)
        #expect(state?.bundleID == "dev.spike.FakePlayer")
    }

    @Test func commandsMapToAdapterArguments() {
        #expect(PlaybackCommand.togglePlayPause.adapterArguments == ["send", "2"])
        #expect(PlaybackCommand.nextTrack.adapterArguments == ["send", "4"])
        #expect(PlaybackCommand.previousTrack.adapterArguments == ["send", "5"])
        #expect(PlaybackCommand.seek(42.25).adapterArguments == ["seek", "42250000"])
        #expect(PlaybackCommand.seek(-3).adapterArguments == ["seek", "0"])
    }
}
