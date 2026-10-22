import Foundation
import IsletCore

/// Paths of the bundled mediaremote-adapter pieces.
struct AdapterPaths {
    var script: URL
    var framework: URL
    var testClient: URL?

    /// Inside the app: Contents/Resources/mediaremote-adapter.pl,
    /// Contents/Frameworks/MediaRemoteAdapter.framework, Contents/Helpers/MediaRemoteAdapterTestClient.
    /// `ISLET_ADAPTER_DIR` overrides the location (used when running from `swift run`).
    static func locate() -> AdapterPaths? {
        let fm = FileManager.default
        if let dir = ProcessInfo.processInfo.environment["ISLET_ADAPTER_DIR"] {
            let base = URL(fileURLWithPath: dir)
            let paths = AdapterPaths(
                script: base.appendingPathComponent("mediaremote-adapter.pl"),
                framework: base.appendingPathComponent("MediaRemoteAdapter.framework"),
                testClient: base.appendingPathComponent("MediaRemoteAdapterTestClient"))
            return paths.exists ? paths : nil
        }
        let bundle = Bundle.main
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = bundle.privateFrameworksURL
        else { return nil }
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/MediaRemoteAdapterTestClient")
        let paths = AdapterPaths(
            script: script,
            framework: frameworks.appendingPathComponent("MediaRemoteAdapter.framework"),
            testClient: fm.isExecutableFile(atPath: helper.path) ? helper : nil)
        return paths.exists ? paths : nil
    }

    var exists: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: script.path) && fm.fileExists(atPath: framework.path)
    }
}

/// Primary source: `/usr/bin/perl mediaremote-adapter.pl <framework> stream`.
///
/// Since macOS 15.4 MediaRemote only answers Apple-signed processes; the system Perl is one of them
/// and loads the small adapter framework that prints JSON lines. Works with every player,
/// browsers and podcast apps. Commands are sent the same way (`send`, `seek`).
final class MediaRemoteAdapterSource: NowPlayingSource {
    let kind = SourceKind.mediaRemote
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    private let paths: AdapterPaths?
    private var process: Process?
    private var testProcess: Process?
    private let parser = AdapterStreamParser()
    private var handler: (@MainActor (NowPlayingSourceEvent) -> Void)?
    private var generation = 0
    private var started = false

    init(paths: AdapterPaths? = AdapterPaths.locate()) {
        self.paths = paths
    }

    func start(_ onEvent: @escaping @MainActor (NowPlayingSourceEvent) -> Void) {
        stop()
        if let paths { Self.killOrphans(script: paths.script) }
        handler = onEvent
        generation += 1
        let token = generation
        started = false
        parser.reset()

        guard let paths else {
            onEvent(.failed("adapter files missing"))
            return
        }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [paths.script.path, paths.framework.path, "stream", "--micros", "--debounce=40"]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(data, token: token) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            // Non-fatal per the adapter docs unless the process exits with an error.
            Log.source.info("adapter stderr: \(String(decoding: data.prefix(500), as: UTF8.self), privacy: .public)")
        }
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.exited(status: status, token: token) }
            }
        }
        do {
            try process.run()
            self.process = process
            Log.source.info("adapter started (pid \(process.processIdentifier))")
        } catch {
            onEvent(.failed("perl: \(error.localizedDescription)"))
            return
        }
        runEntitlementTest(paths, token: token)
    }

    /// A previous Islet that crashed leaves its `perl … stream` behind (re-parented to launchd).
    /// Those are ours by script path; stop them before starting a new one.
    private static func killOrphans(script: URL) {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), parts[1] == "1",
                  parts[2].hasPrefix(perl.path), parts[2].contains(script.path), parts[2].contains(" stream")
            else { continue }
            Log.source.info("stopping orphaned adapter \(pid)")
            kill(pid, SIGTERM)
        }
    }

    func stop() {
        generation += 1
        handler = nil
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        process = nil
        if let testProcess, testProcess.isRunning { testProcess.terminate() }
        testProcess = nil
    }

    func perform(_ command: PlaybackCommand) {
        guard let paths else { return }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [paths.script.path, paths.framework.path] + command.adapterArguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            if proc.terminationStatus != 0 {
                Log.source.error("adapter command failed with \(proc.terminationStatus)")
            }
        }
        do { try process.run() } catch {
            Log.source.error("adapter command: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func consume(_ data: Data, token: Int) {
        guard token == generation, let handler else { return }
        for output in parser.feed(data) {
            switch output {
            case .update(let state):
                if !started {
                    started = true
                    handler(.started)
                }
                handler(.update(state))
            case .malformed:
                Log.source.error("adapter: malformed line (\(self.parser.malformedLines) so far)")
            case .ignored:
                break
            }
        }
    }

    private func exited(status: Int32, token: Int) {
        guard token == generation else { return }
        process = nil
        Log.source.error("adapter exited with \(status)")
        handler?(.failed("adapter exited (\(status))"))
    }

    /// The adapter's own check: can Perl still read MediaRemote? Without it, a blocked MediaRemote
    /// would look like "nothing is playing" forever instead of switching to the fallback.
    private func runEntitlementTest(_ paths: AdapterPaths, token: Int) {
        guard let client = paths.testClient else { return }
        let test = Process()
        test.executableURL = Self.perl
        test.arguments = [paths.script.path, paths.framework.path, client.path, "test"]
        test.standardOutput = FileHandle.nullDevice
        test.standardError = FileHandle.nullDevice
        test.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    self.testProcess = nil
                    if status != 0 {
                        Log.source.error("adapter test failed with \(status)")
                        let handler = self.handler
                        self.stop()
                        handler?(.failed("MediaRemote test failed (\(status))"))
                    } else {
                        Log.source.info("adapter test passed")
                    }
                }
            }
        }
        do {
            try test.run()
            testProcess = test
        } catch {
            Log.source.error("adapter test: \(error.localizedDescription, privacy: .public)")
        }
    }
}
