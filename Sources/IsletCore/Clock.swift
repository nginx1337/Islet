import Foundation

/// A pending delayed action that can be cancelled.
@MainActor
public protocol ScheduledTask: AnyObject {
    func cancel()
}

/// Time source for every delay in the app. The real one uses the main queue,
/// tests use ``ManualClock`` and move time forward without waiting.
@MainActor
public protocol IslandClock: AnyObject {
    var now: Date { get }
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTask
}

/// Main-queue clock. Nothing runs between scheduled actions, so an idle island costs nothing.
@MainActor
public final class SystemClock: IslandClock {
    public init() {}

    public var now: Date { Date() }

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        let task = DispatchTask(action: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: task.item)
        return task
    }

    private final class DispatchTask: ScheduledTask {
        let item: DispatchWorkItem
        init(action: @escaping @MainActor () -> Void) {
            item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        }
        func cancel() { item.cancel() }
    }
}

/// Deterministic clock for tests: time moves only through ``advance(by:)``.
@MainActor
public final class ManualClock: IslandClock {
    public private(set) var now: Date
    private var pending: [Entry] = []
    private var sequence = 0

    public init(start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        now = start
    }

    /// Number of actions still waiting (cancelled ones are not counted).
    public var pendingCount: Int { pending.filter { !$0.task.isCancelled }.count }

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        sequence += 1
        let task = Task(action: action)
        pending.append(Entry(due: now.addingTimeInterval(max(0, delay)), order: sequence, task: task))
        return task
    }

    /// Moves time forward, running every due action in order (including ones they schedule).
    public func advance(by interval: TimeInterval) {
        let target = now.addingTimeInterval(interval)
        while true {
            pending.removeAll { $0.task.isCancelled }
            guard let next = pending.min(by: { ($0.due, $0.order) < ($1.due, $1.order) }), next.due <= target else { break }
            pending.removeAll { $0.task === next.task }
            now = next.due
            next.task.run()
        }
        now = target
    }

    private struct Entry {
        let due: Date
        let order: Int
        let task: Task
    }

    private final class Task: ScheduledTask {
        private var action: (@MainActor () -> Void)?
        init(action: @escaping @MainActor () -> Void) { self.action = action }
        var isCancelled: Bool { action == nil }
        func cancel() { action = nil }
        func run() {
            let action = self.action
            self.action = nil
            action?()
        }
    }
}
