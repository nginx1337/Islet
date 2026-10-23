import AppKit
import IsletCore
import Observation

/// What the island views need from the activity centre: the activity in the capsule
/// and the actions of the capsule's buttons.
@Observable
final class ActivityModel {
    private(set) var current: LiveActivity?

    @ObservationIgnored private let center: ActivityCenter?
    /// The set of activities changed (the coordinator turns pointer tracking on or off).
    @ObservationIgnored var onChange: (() -> Void)?

    /// Without a centre (previews) nothing is ever shown.
    init(center: ActivityCenter? = nil) {
        self.center = center
        center?.onChange = { [weak self] in self?.refresh() }
    }

    private func refresh() {
        let all = center?.activities ?? []
        let new = all.first
        if new != current { current = new }
        onChange?()
    }

    // MARK: Actions

    func startTimer(minutes: Double) {
        center?.startTimer(duration: minutes * 60)
    }

    func startStopwatch() {
        center?.startStopwatch()
    }

    var hasTimer: Bool { center?.activity(.timer) != nil }
    var hasStopwatch: Bool { center?.activity(.stopwatch) != nil }

    /// Tap on the capsule: pause or resume a timer or stopwatch, dismiss anything else.
    func primaryAction() {
        guard let kind = current?.kind else { return }
        switch kind {
        case .timer: center?.toggleTimer()
        case .stopwatch: center?.toggleStopwatch()
        case .power, .headphones, .transfer: center?.dismiss(kind)
        }
    }

    /// The ✕ button.
    func dismissCurrent() {
        guard let kind = current?.kind else { return }
        center?.dismiss(kind)
    }

    func dismiss(_ kind: ActivityKind) {
        center?.dismiss(kind)
    }
}
