import AppKit
import IsletCore

/// Fallback source for when the MediaRemote workaround stops working on a future macOS:
/// Apple Music and Spotify announce track changes with distributed notifications, and
/// AppleScript fills in position and artwork and sends commands.
///
/// It never launches a player: every script runs only while the app is already open.
/// macOS asks once for permission to control each app (Automation).
final class MusicSpotifySource: NowPlayingSource {
    let kind = SourceKind.musicSpotify

    enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var notification: Notification.Name {
            switch self {
            case .music: Notification.Name("com.apple.Music.playerInfo")
            case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }

        var scriptName: String {
            switch self {
            case .music: "Music"
            case .spotify: "Spotify"
            }
        }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
        }
    }

    private var handler: (@MainActor (NowPlayingSourceEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var states: [Player: NowPlayingState] = [:]
    private var lastActive: Player?
    private var artworkTrack: [Player: String] = [:]

    func start(_ onEvent: @escaping @MainActor (NowPlayingSourceEvent) -> Void) {
        stop()
        handler = onEvent
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            observers.append(center.addObserver(forName: player.notification, object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo.map(Self.plain) ?? [:]
                MainActor.assumeIsolated { self?.received(info, from: player) }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let bundle, let player = Player(rawValue: bundle) else { return }
                self.states[player] = nil
                self.publish()
            }
        })
        onEvent(.started)
        // Pick up whatever is already playing.
        for player in Player.allCases where player.isRunning {
            if let state = queryState(of: player) {
                states[player] = state
                if state.isPlaying { lastActive = player }
            }
        }
        for player in Player.allCases where states[player] != nil { loadArtwork(for: player) }
        publish()
    }

    func stop() {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        handler = nil
        states.removeAll()
    }

    func perform(_ command: PlaybackCommand) {
        guard let player = currentPlayer, player.isRunning else { return }
        let verb: String = switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        case .seek(let seconds): "set player position to \(String(format: "%.2f", max(0, seconds)))"
        }
        _ = run("tell application \"\(player.scriptName)\" to \(verb)")
        if case .seek = command, let state = queryState(of: player) {
            states[player] = merge(state, into: states[player])
            publish()
        }
    }

    // MARK: Notifications

    nonisolated private static func plain(_ info: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in info {
            guard let key = key as? String else { continue }
            switch value {
            case let s as String: result[key] = s
            case let n as NSNumber: result[key] = n.stringValue
            default: break
            }
        }
        return result
    }

    private func received(_ info: [String: String], from player: Player) {
        let stateText = info["Player State"] ?? ""
        guard stateText != "Stopped", let title = info["Name"], !title.isEmpty else {
            states[player] = nil
            publish()
            return
        }
        let playing = stateText == "Playing"
        let durationMS = Double(info["Total Time"] ?? info["Duration"] ?? "")
        var state = NowPlayingState(
            bundleID: player.rawValue, title: title,
            artist: info["Artist"] ?? "", album: info["Album"] ?? "",
            duration: durationMS.map { $0 / 1000 },
            elapsed: Double(info["Playback Position"] ?? ""),
            timestamp: Date(), rate: playing ? 1 : 0, isPlaying: playing)
        if state.elapsed == nil, let position = queryPosition(of: player) {
            state.elapsed = position
            state.timestamp = Date()
        }
        states[player] = merge(state, into: states[player])
        if playing { lastActive = player }
        loadArtwork(for: player)
        publish()
    }

    /// Keeps artwork of the same track when a new notification does not carry it.
    private func merge(_ new: NowPlayingState, into old: NowPlayingState?) -> NowPlayingState {
        var result = new
        if let old, old.trackID == new.trackID {
            result.artworkData = result.artworkData ?? old.artworkData
            result.artworkURL = result.artworkURL ?? old.artworkURL
        }
        return result
    }

    private var currentPlayer: Player? {
        if let lastActive, states[lastActive]?.isPlaying == true { return lastActive }
        if let playing = Player.allCases.first(where: { states[$0]?.isPlaying == true }) { return playing }
        if let lastActive, states[lastActive] != nil { return lastActive }
        return Player.allCases.first { states[$0] != nil }
    }

    private func publish() {
        handler?(.update(currentPlayer.flatMap { states[$0] }))
    }

    // MARK: AppleScript

    private func queryState(of player: Player) -> NowPlayingState? {
        let name = player.scriptName
        let script = """
        tell application "\(name)"
            if player state is stopped then return ""
            set sep to character id 31
            set t to current track
            set d to duration of t
            return (name of t) & sep & (artist of t) & sep & (album of t) & sep & (d as text) & sep & (player position as text) & sep & (player state as text)
        end tell
        """
        guard let text = run(script)?.stringValue, !text.isEmpty else { return nil }
        let parts = text.components(separatedBy: "\u{1F}")
        guard parts.count == 6, !parts[0].isEmpty else { return nil }
        let playing = parts[5] == "playing"
        var duration = Self.number(parts[3])
        // Spotify reports milliseconds, Music seconds.
        if player == .spotify { duration = duration.map { $0 / 1000 } }
        return NowPlayingState(
            bundleID: player.rawValue, title: parts[0], artist: parts[1], album: parts[2],
            duration: duration, elapsed: Self.number(parts[4]), timestamp: Date(),
            rate: playing ? 1 : 0, isPlaying: playing)
    }

    private func queryPosition(of player: Player) -> Double? {
        guard player.isRunning, let text = run("tell application \"\(player.scriptName)\" to return player position as text")?.stringValue
        else { return nil }
        return Self.number(text)
    }

    /// AppleScript numbers follow the system locale ("12,5" in Russian).
    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func loadArtwork(for player: Player) {
        guard let state = states[player], artworkTrack[player] != state.trackID, player.isRunning else { return }
        artworkTrack[player] = state.trackID
        switch player {
        case .music:
            let script = "tell application \"Music\" to if (count of artworks of current track) > 0 then return raw data of artwork 1 of current track"
            if let data = run(script)?.data, !data.isEmpty {
                states[player]?.artworkData = data
            }
        case .spotify:
            if let text = run("tell application \"Spotify\" to return artwork url of current track")?.stringValue,
               let url = URL(string: text), url.scheme == "https" {
                states[player]?.artworkURL = url
            }
        }
    }

    @discardableResult
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.source.error("AppleScript: \(String(describing: error[NSAppleScript.errorMessage] ?? error), privacy: .public)")
        }
        return result
    }
}
