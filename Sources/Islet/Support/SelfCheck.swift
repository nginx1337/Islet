import AppKit
import IsletCore

/// `Islet --self-check`: starts the app for real (source, panels), waits for the data source to
/// settle, prints what it sees and exits. Exit code 0 means the app works on this Mac.
enum SelfCheck {
    static let timeout: TimeInterval = 10

    static func run(model: AppModel) {
        let started = Date()
        func poll() {
            let status = model.media.sourceStatus
            let settled = status != .starting
            if settled || Date().timeIntervalSince(started) > timeout {
                // Give the first state a moment to reach the islands.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated { finish(model: model) }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    MainActor.assumeIsolated { poll() }
                }
            }
        }
        poll()
    }

    private static func finish(model: AppModel) {
        var lines: [String] = []
        var ok = true
        let status = model.media.sourceStatus
        lines.append("Islet self-check")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("adapter files: \(AdapterPaths.locate() != nil ? "found" : "missing")")
        switch status {
        case .primary: lines.append("source: primary (MediaRemote adapter)")
        case .fallback(let reason): lines.append("source: fallback (Music/Spotify), reason: \(reason)")
        case .starting:
            lines.append("source: did not start within \(Int(timeout)) s")
            ok = false
        case .unavailable(let reason):
            lines.append("source: unavailable, reason: \(reason)")
            ok = false
        }
        if let state = model.media.state {
            let position = PlaybackTimeline.format(PlaybackTimeline.position(of: state, at: Date()))
            let duration = state.duration.map(PlaybackTimeline.format) ?? "live"
            lines.append("now playing: \"\(state.title)\" — \(state.artist.isEmpty ? "?" : state.artist) [\(state.bundleID ?? "?")] \(state.isPlaying ? "playing" : "paused") \(position)/\(duration), artwork: \(state.artworkData != nil || state.artworkURL != nil ? "yes" : "no")")
        } else {
            lines.append("now playing: nothing")
        }
        let screens = ScreenReader.descriptors()
        lines.append("screens: \(screens.count)")
        for screen in screens {
            let layout = IslandLayoutEngine.layout(for: screen, settings: model.settings.layoutSettings)
            lines.append("  \(screen.isBuiltIn ? "built-in" : "external") \(Int(screen.frame.width))×\(Int(screen.frame.height)) @\(Int(screen.backingScale))x, menu bar \(Int(screen.menuBarHeight)) pt → \(layout.style.rawValue), compact \(Int(layout.compact.frame.width))×\(Int(layout.compact.frame.height))")
        }
        let islands = model.islands.controllers.values
        lines.append("islands: \(islands.count) (" + islands.map { "\($0.presentation)" }.joined(separator: ", ") + ")")
        if islands.count != model.islands.layouts.count {
            lines.append("error: \(model.islands.layouts.count) layouts but \(islands.count) panels")
            ok = false
        }
        // A playing track must make every island visible.
        if model.media.state?.isPlaying == true, islands.contains(where: { $0.presentation.isHidden }) {
            lines.append("error: media is playing but an island is hidden")
            ok = false
        }
        lines.append(ok ? "result: OK" : "result: FAILED")
        print(lines.joined(separator: "\n"))
        fflush(stdout)
        model.shutdown()
        exit(ok ? 0 : 1)
    }
}
