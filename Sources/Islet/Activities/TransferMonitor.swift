import Foundation
import IsletCore

/// Shows the progress of file operations that other apps publish through `Progress`
/// (Finder copies, Safari downloads, AirDrop). Public API; it only reads the published
/// fraction and kind, never file names or contents.
///
/// It listens for operations on files in Downloads, Desktop, Documents and on mounted volumes.
/// Which operations an app publishes is up to that app; operations that publish nothing are not shown.
final class TransferMonitor {
    /// Aggregated progress of everything running, or nil when nothing runs.
    var onUpdate: ((TransferInfo?) -> Void)?

    /// More than this many operations at once are ignored: a safety limit, not a feature.
    private static let maxTracked = 16
    private static let pollInterval: TimeInterval = 0.5

    private let clock: IslandClock
    private var subscribers: [Any] = []
    private var tracked: [(id: ObjectIdentifier, progress: Progress)] = []
    private var poll: ScheduledTask?
    private var lastPublished: TransferInfo?

    init(clock: IslandClock) {
        self.clock = clock
    }

    var isRunning: Bool { !subscribers.isEmpty }

    func start() {
        guard subscribers.isEmpty else { return }
        for url in Self.watchedFolders() {
            subscribers.append(Self.subscribe(
                to: url,
                began: { [weak self] box in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.begin(box.progress) } }
                },
                ended: { [weak self] id in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.end(id) } }
                }))
        }
    }

    func stop() {
        for subscriber in subscribers { Progress.removeSubscriber(subscriber) }
        subscribers.removeAll()
        poll?.cancel()
        poll = nil
        tracked.removeAll()
        publish(force: true)
    }

    private static func watchedFolders() -> [URL] {
        let manager = FileManager.default
        var urls: [URL] = []
        for directory in [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory] {
            urls.append(contentsOf: manager.urls(for: directory, in: .userDomainMask))
        }
        urls.append(URL(fileURLWithPath: "/Volumes", isDirectory: true))
        return urls
    }

    /// Built outside the main actor on purpose: Foundation calls the handlers on whatever thread
    /// publishes the progress, so they must not be main-actor closures.
    nonisolated private static func subscribe(
        to url: URL,
        began: @escaping @Sendable (ProgressBox) -> Void,
        ended: @escaping @Sendable (ObjectIdentifier) -> Void
    ) -> Any {
        Progress.addSubscriber(forFileURL: url) { progress in
            began(ProgressBox(progress))
            let id = ObjectIdentifier(progress)
            return { ended(id) }
        }
    }

    // MARK: Tracking

    private func begin(_ progress: Progress) {
        let id = ObjectIdentifier(progress)
        guard tracked.count < Self.maxTracked, !tracked.contains(where: { $0.id == id }) else { return }
        tracked.append((id, progress))
        publish()
        armPoll()
    }

    private func end(_ id: ObjectIdentifier) {
        tracked.removeAll { $0.id == id }
        publish()
    }

    /// Progress objects are read twice a second, and only while something is running.
    private func armPoll() {
        guard poll == nil, !tracked.isEmpty else { return }
        poll = clock.schedule(after: Self.pollInterval) { [weak self] in
            guard let self else { return }
            self.poll = nil
            self.tracked.removeAll { $0.progress.isFinished || $0.progress.isCancelled }
            self.publish()
            self.armPoll()
        }
    }

    private func publish(force: Bool = false) {
        let info = Self.aggregate(tracked.map(\.progress))
        guard force || info != lastPublished else { return }
        lastPublished = info
        onUpdate?(info)
    }

    /// Mean progress of the operations whose size is known (in 1 % steps, so small changes do not
    /// redraw the island); the kind of the first one.
    private static func aggregate(_ progresses: [Progress]) -> TransferInfo? {
        let active = progresses.filter { !$0.isFinished && !$0.isCancelled }
        guard let first = active.first else { return nil }
        let known = active.filter { !$0.isIndeterminate }.map(\.fractionCompleted)
        let fraction = known.isEmpty ? nil : (known.reduce(0, +) / Double(known.count) * 100).rounded() / 100
        return TransferInfo(operation: operation(of: first), fraction: fraction)
    }

    private static func operation(of progress: Progress) -> TransferInfo.Operation {
        guard let kind = progress.fileOperationKind else { return .other }
        switch kind {
        case .downloading, .receiving, .decompressingAfterDownloading: return .download
        case .copying, .duplicating: return .copy
        default: return .other
        }
    }
}

/// `Progress` is thread-safe but not marked `Sendable`.
nonisolated struct ProgressBox: @unchecked Sendable {
    let progress: Progress
    init(_ progress: Progress) { self.progress = progress }
}
