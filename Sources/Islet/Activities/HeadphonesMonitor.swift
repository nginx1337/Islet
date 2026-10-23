import CoreAudio
import Foundation
import IsletCore

/// Announces when a Bluetooth device becomes the default output (AirPods, headphones, a speaker).
/// Core Audio public API; needs no permission and does not touch Bluetooth itself, so there is no
/// battery level, only the device name.
final class HeadphonesMonitor {
    var onConnect: ((String) -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
    private var lastDevice = AudioObjectID(kAudioObjectUnknown)

    private static var outputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    func start() {
        guard listener == nil else { return }
        lastDevice = Self.defaultOutput()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.outputChanged() }
            }
        }
        listener = block
        var address = Self.outputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }

    func stop() {
        guard let listener else { return }
        var address = Self.outputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        self.listener = nil
    }

    private func outputChanged() {
        let device = Self.defaultOutput()
        guard device != lastDevice else { return }
        lastDevice = device
        guard device != AudioObjectID(kAudioObjectUnknown), Self.isBluetooth(device) else { return }
        onConnect?(TimeFormat.displayName(Self.name(of: device) ?? ""))
    }

    private static func defaultOutput() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = outputAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
