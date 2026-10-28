import Foundation
import IsletCore

/// A source that reports one fixed state and ignores every command. The settings preview uses it
/// when nothing plays, and the debug preview renderer for its pictures.
final class SampleSource: NowPlayingSource {
    let kind = SourceKind.mediaRemote
    let state: NowPlayingState?

    init(state: NowPlayingState?) {
        self.state = state
    }

    func start(_ onEvent: @escaping @MainActor (NowPlayingSourceEvent) -> Void) {
        onEvent(.started)
        onEvent(.update(state))
    }

    func stop() {}
    func perform(_ command: PlaybackCommand) {}
}
