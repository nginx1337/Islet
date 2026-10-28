import Foundation
import IOKit.ps
import IsletCore

/// Plug, unplug and low-battery notices from the system power sources (IOKit, public API).
/// Needs no permission. A Mac without a battery never reports anything.
final class PowerMonitor {
    /// Default percentage at which the low-battery notice appears while on battery.
    static let defaultLowThreshold = 20
    /// Thresholds the settings offer.
    static let lowThresholdChoices = [10, 15, 20, 25, 30]

    /// Percentage at which the low-battery notice appears while on battery (kept to 5…50).
    var lowThreshold = PowerMonitor.defaultLowThreshold {
        didSet { lowThreshold = min(max(lowThreshold, 5), 50) }
    }
    /// Announce plugging the charger in and out.
    var announcesCharger = true
    /// Announce a low battery.
    var announcesLowBattery = true

    var onNotice: ((PowerInfo) -> Void)?
    private var source: CFRunLoopSource?
    private var lastOnAC: Bool?
    private var lowWarned = false

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() else { return }
        source = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        // The first reading is the baseline: nothing is announced for the state the app starts in.
        lastOnAC = read()?.onAC
    }

    func stop() {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = nil
        lastOnAC = nil
        lowWarned = false
    }

    fileprivate func changed() {
        guard let now = read() else { return }
        defer { lastOnAC = now.onAC }
        guard let before = lastOnAC else { return }
        if now.onAC != before {
            lowWarned = false
            if announcesCharger {
                onNotice?(PowerInfo(event: now.onAC ? .pluggedIn : .unplugged, percent: now.percent))
            }
            return
        }
        if now.onAC {
            lowWarned = false
        } else if now.percent <= lowThreshold {
            if !lowWarned {
                lowWarned = true
                if announcesLowBattery { onNotice?(PowerInfo(event: .low, percent: now.percent)) }
            }
        } else if now.percent > lowThreshold + 5 {
            lowWarned = false
        }
    }

    /// The internal battery: on mains power or not, and the charge in percent.
    private func read() -> (onAC: Bool, percent: Int)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let capacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = capacity > 0 ? min(max(current * 100 / capacity, 0), 100) : 0
            let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (onAC, percent)
        }
        return nil
    }
}

nonisolated private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.changed() }
}
