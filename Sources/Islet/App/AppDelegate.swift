import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private let selfCheck: Bool

    init(selfCheck: Bool) {
        self.selfCheck = selfCheck
    }

    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill`/`pkill` and logout send SIGTERM: quit normally so the adapter and audio tap stop too.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        termSource = source

        // A newer copy replaces an older one: ask any other running Islet to quit, so two islands never
        // fight over the screen. Not in --self-check, which must not touch the installed app.
        if !selfCheck { Self.quitOtherInstances() }

        let model = AppModel()
        self.model = model
        model.start(withMenu: !selfCheck)
        if selfCheck { SelfCheck.run(model: model) }
    }

    /// Asks other running copies with the same bundle identifier to quit (a normal quit, not a kill).
    private static func quitOtherInstances() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) where app.processIdentifier != me {
            app.terminate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    /// Opening Islet again (Finder, Spotlight) shows the settings: there is no other window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showSettings()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
