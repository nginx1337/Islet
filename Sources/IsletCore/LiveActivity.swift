import Foundation

/// What kind of live activity the second capsule shows. At most one of each kind exists.
public enum ActivityKind: String, CaseIterable, Sendable {
    case timer, stopwatch, power, headphones, transfer
}

/// Countdown timer. All times are absolute dates, so nothing has to tick to keep it correct.
public struct CountdownTimer: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    public static let minDuration: TimeInterval = 1
    public static let maxDuration: TimeInterval = 24 * 3600

    public let total: TimeInterval
    public private(set) var phase: Phase

    /// A running timer. The duration is clamped to 1 s … 24 h; NaN and infinity fall back to one minute.
    public init(duration: TimeInterval, startingAt now: Date) {
        let safe = duration.isFinite ? duration : 60
        total = min(max(safe, Self.minDuration), Self.maxDuration)
        phase = .running(endsAt: now.addingTimeInterval(total))
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .paused(let remaining): remaining
        case .finished: 0
        }
    }

    /// Fraction of the time that is left, 1 at the start and 0 at the end.
    public func fractionLeft(at now: Date) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining(at: now) / total))
    }

    public var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    public var isFinished: Bool { phase == .finished }

    /// A running timer whose end has come.
    public func hasEnded(at now: Date) -> Bool {
        guard case .running(let end) = phase else { return false }
        return end <= now
    }

    public mutating func pause(at now: Date) {
        guard case .running = phase else { return }
        phase = .paused(remaining: remaining(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let remaining) = phase else { return }
        phase = .running(endsAt: now.addingTimeInterval(remaining))
    }

    public mutating func finish() {
        phase = .finished
    }
}

/// Stopwatch with the same absolute-date approach.
public struct Stopwatch: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case running(since: Date, accumulated: TimeInterval)
        case paused(accumulated: TimeInterval)
    }

    public private(set) var phase: Phase

    public init(startingAt now: Date) {
        phase = .running(since: now, accumulated: 0)
    }

    public func elapsed(at now: Date) -> TimeInterval {
        switch phase {
        case .running(let since, let accumulated): max(0, accumulated + now.timeIntervalSince(since))
        case .paused(let accumulated): accumulated
        }
    }

    public var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    public mutating func pause(at now: Date) {
        guard case .running = phase else { return }
        phase = .paused(accumulated: elapsed(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let accumulated) = phase else { return }
        phase = .running(since: now, accumulated: accumulated)
    }
}

public struct PowerInfo: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case pluggedIn, unplugged, low
    }

    public var event: Event
    /// 0…100.
    public var percent: Int

    public init(event: Event, percent: Int) {
        self.event = event
        self.percent = min(max(percent, 0), 100)
    }
}

public struct TransferInfo: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case download, copy, other
    }

    public var operation: Operation
    /// 0…1, or nil when the size is unknown.
    public var fraction: Double?

    public init(operation: Operation, fraction: Double?) {
        self.operation = operation
        self.fraction = fraction.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
    }
}

public enum ActivityContent: Equatable, Sendable {
    case countdown(CountdownTimer)
    case stopwatch(Stopwatch)
    case power(PowerInfo)
    /// Bluetooth headphones became the output device. The name is cut to a displayable length.
    case headphones(name: String)
    case transfer(TransferInfo)

    public var kind: ActivityKind {
        switch self {
        case .countdown: .timer
        case .stopwatch: .stopwatch
        case .power: .power
        case .headphones: .headphones
        case .transfer: .transfer
        }
    }

    /// Higher wins the capsule when several activities exist.
    var priority: Int {
        switch self {
        case .countdown(let timer): timer.isFinished ? 100 : 60
        case .power: 80
        case .headphones: 70
        case .stopwatch: 40
        case .transfer: 30
        }
    }
}

public struct LiveActivity: Equatable, Sendable, Identifiable {
    public var content: ActivityContent
    public var postedAt: Date

    public var kind: ActivityKind { content.kind }
    public var id: String { kind.rawValue }

    public init(content: ActivityContent, postedAt: Date) {
        self.content = content
        self.postedAt = postedAt
    }
}

public enum TimeFormat {
    /// "4:59", "1:02:03". Rounds up when `roundingUp` so a countdown shows 0:00 only at the very end.
    public static func clock(_ seconds: TimeInterval, roundingUp: Bool = false) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let whole = Int(min(seconds, 99 * 3600 + 3599))
        let total = roundingUp && seconds > Double(whole) ? whole + 1 : whole
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? "\(h):" + twoDigits(m) + ":" + twoDigits(s)
            : "\(m):" + twoDigits(s)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// A device or file label cut to `limit` characters, with control characters removed.
    public static func displayName(_ raw: String, limit: Int = 24) -> String {
        let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit - 1)) + "…"
    }
}
