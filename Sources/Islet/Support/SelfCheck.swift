import AppKit
import IsletCore

/// `Islet --self-check`: starts the app for real (source, panels), waits for the data source to
/// settle, prints what it sees and exits. Exit code 0 means the app works on this Mac.
enum SelfCheck {
    static let timeout: TimeInterval = 15

    static func run(model: AppModel) {
        let started = Date()
        func poll() {
            let status = model.media.sourceStatus
            // "Primary" alone is not enough: a blocked MediaRemote also streams (empty) data.
            // Wait for the adapter's own check, which takes a few seconds when it fails.
            let settled = switch status {
            case .starting: false
            case .primary: MediaRemoteAdapterSource.entitlementTest.isFinished
            case .fallback, .unavailable: true
            }
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
        var degraded = false
        let status = model.media.sourceStatus
        lines.append("Islet self-check")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("adapter files: \(AdapterPaths.locate() != nil ? "found" : "missing")")
        switch status {
        case .primary:
            lines.append("source: primary (MediaRemote adapter), check: \(MediaRemoteAdapterSource.entitlementTest)")
            if !MediaRemoteAdapterSource.entitlementTest.isFinished {
                lines.append("error: the adapter check did not finish within \(Int(timeout)) s")
                ok = false
            }
        case .fallback(let reason):
            lines.append("source: fallback (Music/Spotify), reason: \(reason)")
            degraded = true
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
        lines.append(!ok ? "result: FAILED" : degraded ? "result: WORKS IN FALLBACK MODE" : "result: OK")
        print(lines.joined(separator: "\n"))
        fflush(stdout)
        model.shutdown()
        // 0: works, 1: broken, 2: works only through the Music/Spotify fallback.
        exit(!ok ? 1 : degraded ? 2 : 0)
    }
}
