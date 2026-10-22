import Foundation

/// Turns the output of `mediaremote-adapter.pl … stream` into ``NowPlayingState`` values.
///
/// The adapter prints one JSON object per line:
/// `{"type":"data","diff":false,"payload":{…}}`. A non-diff payload replaces the state,
/// a diff payload is merged into it, and a key set to `null` in a diff is removed.
/// An empty non-diff payload means nothing is playing.
///
/// Bytes can arrive in arbitrary chunks, so a line is only parsed once its newline arrives.
public final class AdapterStreamParser {
    public enum Output: Equatable {
        /// The merged state changed (`nil`: nothing is playing).
        case update(NowPlayingState?)
        /// A valid line that we do not use (another `type`).
        case ignored
        /// A line that is not valid adapter JSON. The current state is kept.
        case malformed
    }

    private var buffer = Data()
    private var payload: [String: Any] = [:]
    private var hasBaseline = false
    public private(set) var malformedLines = 0
    public private(set) var parsedLines = 0

    /// Upper bound for one line, so a broken stream without newlines cannot eat memory.
    /// Artwork arrives inline as base64 and is usually well under 2 MB.
    public static let maxLineBytes = 16 * 1024 * 1024

    public init() {}

    /// Feeds raw bytes and returns one output per completed line.
    public func feed(_ chunk: Data) -> [Output] {
        buffer.append(chunk)
        var outputs: [Output] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            outputs.append(parse(line: Data(line)))
        }
        if buffer.count > Self.maxLineBytes {
            buffer.removeAll(keepingCapacity: false)
            malformedLines += 1
            outputs.append(.malformed)
        }
        return outputs
    }

    /// Feeds a string (convenient for tests and for `get`, which prints a single line).
    public func feed(_ text: String) -> [Output] {
        feed(Data(text.utf8))
    }

    /// Forgets everything (used when the adapter process restarts).
    public func reset() {
        buffer.removeAll()
        payload = [:]
        hasBaseline = false
    }

    public var currentState: NowPlayingState? {
        Self.state(from: payload)
    }

    private func parse(line: Data) -> Output {
        guard
            let object = try? JSONSerialization.jsonObject(with: line, options: [.fragmentsAllowed]),
            let message = object as? [String: Any],
            let type = message["type"] as? String
        else {
            malformedLines += 1
            return .malformed
        }
        guard type == "data" else { return .ignored }
        guard let incoming = message["payload"] as? [String: Any] else {
            malformedLines += 1
            return .malformed
        }
        parsedLines += 1
        let isDiff = (message["diff"] as? Bool) ?? false
        if isDiff && hasBaseline {
            for (key, value) in incoming {
                if value is NSNull { payload.removeValue(forKey: key) } else { payload[key] = value }
            }
        } else {
            payload = incoming.filter { !($0.value is NSNull) }
            hasBaseline = true
        }
        return .update(Self.state(from: payload))
    }

    /// Maps one adapter payload (as from `get` or a merged stream state) to a state.
    public static func state(from payload: [String: Any]) -> NowPlayingState? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        let bundle = (payload["parentApplicationBundleIdentifier"] as? String)
            ?? (payload["bundleIdentifier"] as? String)
        let playing = (payload["playing"] as? Bool) ?? false

        func seconds(_ key: String, microsKey: String) -> TimeInterval? {
            if let micros = number(payload[microsKey]) { return micros / 1_000_000 }
            return number(payload[key])
        }

        var timestamp: Date?
        if let micros = number(payload["timestampEpochMicros"]) {
            timestamp = Date(timeIntervalSince1970: micros / 1_000_000)
        } else if let iso = payload["timestamp"] as? String {
            timestamp = isoDate(iso)
        }

        var artwork: Data?
        if let base64 = payload["artworkData"] as? String, !base64.isEmpty {
            artwork = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        }

        let duration = seconds("duration", microsKey: "durationMicros")
        return NowPlayingState(
            bundleID: bundle,
            title: title,
            artist: (payload["artist"] as? String) ?? "",
            album: (payload["album"] as? String) ?? "",
            artworkData: artwork,
            duration: (duration ?? 0) > 0 ? duration : nil,
            elapsed: seconds("elapsedTime", microsKey: "elapsedTimeMicros"),
            timestamp: timestamp,
            rate: number(payload["playbackRate"]) ?? (playing ? 1 : 0),
            isPlaying: playing
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }

    private static func isoDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
