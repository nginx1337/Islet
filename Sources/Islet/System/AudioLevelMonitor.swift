import AppKit
import AudioToolbox
import CoreAudio
import IsletCore

/// Listens to what the Mac plays (a Core Audio process tap: read-only, the sound is not changed)
/// and drives the equaliser bars with real bass/mid/treble levels.
///
/// Runs only while a compact island is visible and something plays. macOS asks once for
/// "System Audio Recording" permission. If it is denied the tap delivers silence, and the bars
/// fall back to the decorative animation.
final class AudioLevelMonitor {
    static let shared = AudioLevelMonitor()

    enum Status: Equatable {
        case off
        case starting
        /// Sound arrives and the bars follow it.
        case live
        /// Running but only silence so far: no permission, or nothing audible.
        case silent
        case failed(String)
    }

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    var onStatusChange: ((Status) -> Void)?

    private let views = NSHashTable<EqualizerNSView>.weakObjects()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var tapUUID = UUID()
    private let queue = DispatchQueue(label: "app.islet.audio-levels", qos: .userInteractive)
    private var deviceListener: AudioObjectPropertyListenerBlock?

    var isRunning: Bool { procID != nil }

    // MARK: Views

    func register(_ view: EqualizerNSView) {
        views.add(view)
        view.setLive(status == .live)
    }

    func unregister(_ view: EqualizerNSView) {
        views.remove(view)
    }

    /// Called on the main queue about 30 times a second while running.
    fileprivate func receive(levels: [Float], signalSeen: Bool) {
        guard isRunning else { return }
        if signalSeen {
            if status != .live {
                status = .live
                Log.system.info("audio levels live: \(levels.map { String(format: "%.2f", $0) }.joined(separator: " "), privacy: .public)")
                for view in views.allObjects { view.setLive(true) }
            }
            for view in views.allObjects { view.apply(levels: levels) }
        } else if status == .starting {
            status = .silent
        }
    }

    // MARK: Start and stop

    func setWanted(_ wanted: Bool) {
        if wanted { start() } else { stop() }
    }

    func start() {
        guard !isRunning else { return }
        status = .starting
        do {
            try createTap()
            installDeviceListener()
            Log.system.info("audio tap started")
        } catch {
            Log.system.error("audio tap: \(error.localizedDescription, privacy: .public)")
            teardown()
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        guard isRunning || tapID != kAudioObjectUnknown else {
            status = .off
            return
        }
        teardown()
        removeDeviceListener()
        status = .off
        for view in views.allObjects { view.setLive(false) }
        Log.system.info("audio tap stopped")
    }

    private struct TapError: LocalizedError {
        let step: String
        let code: OSStatus
        var errorDescription: String? { "\(step) failed (\(code))" }
    }

    private func check(_ code: OSStatus, _ step: String) throws {
        if code != noErr { throw TapError(step: step, code: code) }
    }

    private func createTap() throws {
        // Everything the Mac plays, mixed to stereo. Private, and the sound keeps playing as usual.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapUUID = UUID()
        description.uuid = tapUUID
        description.name = "Islet levels"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")

        let (outputDevice, outputUID) = try defaultOutput()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Islet Levels",
            kAudioAggregateDeviceUIDKey: "app.islet.levels.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUUID.uuidString
            ]]
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "AudioHardwareCreateAggregateDevice")

        // The aggregate's input lists the output device's own inputs first (the microphone of a
        // USB headset or audio interface), then the tap. Those inputs are switched off for our
        // callback and skipped, so the microphone is never opened or measured.
        let deviceInputs = inputStreamCount(of: outputDevice)
        let allInputs = inputStreamCount(of: aggregateID)
        let skip = min(deviceInputs, max(0, allInputs - 1))

        let format = try tapFormat()
        let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate)
        let mixer = MonoMixer(analyzer: analyzer, skipBuffers: skip)
        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue, Self.ioBlock(mixer)),
                  "AudioDeviceCreateIOProcIDWithBlock")
        procID = proc
        if skip > 0, let proc {
            try check(switchOffInputs(first: skip, for: proc), "switch off device inputs")
            Log.system.info("audio tap: \(skip) device input stream(s) switched off")
        }
        try check(AudioDeviceStart(aggregateID, proc), "AudioDeviceStart")
    }

    /// Built outside the main actor: Core Audio calls it on its own real-time thread.
    nonisolated private static func ioBlock(_ mixer: MonoMixer) -> AudioDeviceIOBlock {
        { _, input, _, _, _ in mixer.consume(input) }
    }

    private func teardown() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func inputStreamCount(of device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    /// Marks the first `count` input streams as unused by our callback (`kAudioDevicePropertyIOProcStreamUsage`).
    private func switchOffInputs(first count: Int, for proc: AudioDeviceIOProcID) -> OSStatus {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIOProcStreamUsage,
            mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(aggregateID, &address, 0, nil, &size)
        guard status == noErr, size >= UInt32(MemoryLayout<AudioHardwareIOProcStreamUsage>.size) else { return status }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(proc, to: UnsafeMutableRawPointer.self)
        status = AudioObjectGetPropertyData(aggregateID, &address, 0, nil, &size, raw)
        guard status == noErr else { return status }
        let streams = Int(usage.pointee.mNumberStreams)
        let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 8 + MemoryLayout<UInt32>.size
        let flags = raw.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        for i in 0..<min(count, streams) { flags[i] = 0 }
        return AudioObjectSetPropertyData(aggregateID, &address, 0, nil, size, raw)
    }

    private func defaultOutput() throws -> (AudioObjectID, String) {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "default output device")
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid), "output device UID")
        guard let uid else { throw TapError(step: "output device UID", code: -1) }
        return (device, uid.takeRetainedValue() as String)
    }

    private func tapFormat() throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "tap format")
        return format
    }

    /// Headphones plugged in or another output chosen: rebuild the tap on the new device.
    private func installDeviceListener() {
        guard deviceListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let monitor = AudioLevelMonitor.shared
                    guard monitor.isRunning else { return }
                    monitor.teardown()
                    monitor.start()
                }
            }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    private func removeDeviceListener() {
        guard let deviceListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        self.deviceListener = nil
    }
}

/// Runs on the audio queue: mixes the tap's buffers to mono, feeds the analyzer and posts
/// levels to the main queue at most 30 times a second.
nonisolated private final class MonoMixer: @unchecked Sendable {
    private let analyzer: SpectrumAnalyzer
    /// Leading buffers that belong to the output device's own inputs (a microphone), never read.
    private let skipBuffers: Int
    private var mono: [Float] = []
    private var lastPost: UInt64 = 0
    private static let postInterval: UInt64 = 33_000_000 // ns

    init(analyzer: SpectrumAnalyzer, skipBuffers: Int) {
        self.analyzer = analyzer
        self.skipBuffers = skipBuffers
    }

    func consume(_ input: UnsafePointer<AudioBufferList>) {
        let all = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard all.count > skipBuffers else { return }
        let buffers = all[skipBuffers...]
        guard let first = buffers.first, first.mDataByteSize > 0 else { return }
        let interleaved = Int(max(1, first.mNumberChannels))
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * interleaved)
        if mono.count != frames { mono = [Float](repeating: 0, count: frames) }
        for i in 0..<frames { mono[i] = 0 }
        var channels = 0
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let n = Int(max(1, buffer.mNumberChannels))
            let count = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * n))
            for i in 0..<count {
                for c in 0..<n { mono[i] += data[i * n + c] }
            }
            channels += n
        }
        guard channels > 0 else { return }
        let gain = 1 / Float(channels)
        for i in 0..<frames { mono[i] *= gain }

        guard mono.withUnsafeBufferPointer({ analyzer.process($0) }) else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastPost >= Self.postInterval else { return }
        lastPost = now
        let levels = analyzer.levels, seen = analyzer.signalSeen
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                AudioLevelMonitor.shared.receive(levels: levels, signalSeen: seen)
            }
        }
    }
}
