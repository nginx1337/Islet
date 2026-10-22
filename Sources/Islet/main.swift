import AppKit

// Islet: "Now Playing" as an island at the top of the screen.
// `--self-check` starts the app, reports what it sees and exits with 0 (OK) or 1.
#if DEBUG
if let index = CommandLine.arguments.firstIndex(of: "--render-preview") {
    // Developer aid (debug builds only): renders the island in every state to PNG files.
    MainActor.assumeIsolated { PreviewRenderer.run(arguments: Array(CommandLine.arguments[(index + 1)...])) }
    exit(0)
}
#endif

let selfCheck = CommandLine.arguments.contains("--self-check")

let application = NSApplication.shared
let appDelegate = AppDelegate(selfCheck: selfCheck)
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
