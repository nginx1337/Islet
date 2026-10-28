<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/banner-dark.png">
  <img src="docs/banner-light.png" alt="Islet — Now Playing as an island at the top of the screen, macOS 27" width="100%">
</picture>

**Islet** shows "Now Playing" as an island at the top of the screen, like Dynamic Island on iPhone. macOS 27.

On a MacBook the island lives in the notch and grows out of it. On an external monitor it is a separate floating pill. Artwork on the left, an equaliser tinted from the artwork on the right. Hover and it expands: large artwork, title, artist, a seek bar and controls. Works with any player: Music, Spotify, browsers, podcasts, VLC, IINA.

[Русская версия](README.md)

<img src="docs/overview.png" width="100%" alt="Islet: Swift 6, SwiftUI, Core Animation, Core Audio. About 7,500 lines, no telemetry, 154 tests, 0% idle CPU. Hover to expand; the bars follow the real sound; click the title to open the player; ⌃⌥⌘N expands and collapses.">

| In the MacBook notch | On an external monitor |
|---|---|
| <img src="docs/notch-compact.png" alt="Compact island in the notch"> | <img src="docs/monitor-compact.png" alt="Compact island on a monitor"> |
| <img src="docs/notch-expanded.png" alt="Expanded island in the notch"> | <img src="docs/monitor-expanded.png" alt="Expanded island on a monitor"> |
| <img src="docs/notch-title-compact.png" alt="Compact island with the title in the notch"> | <img src="docs/monitor-title-compact.png" alt="Compact island with the title on a monitor"> |

## Behaviour

- **Nothing playing**: hidden. In the notch it matches the notch and is invisible; on a monitor it shrinks to a point and fades out.
- **Playing**: compact, with artwork and equaliser. Six bars, as on the iPhone, show the Mac's real sound: bass on the left, highs on the right. Without System Audio Recording permission they just animate.
- **Title in the compact island** (a setting): between the artwork and the bars, tinted from the artwork. A long title scrolls and fades out at the edges.
- **New track**: expands by itself for 3 seconds.
- **Hover or click**: expands; collapses 0.4 s after the pointer leaves.
- **Paused**: dims, then hides after 15 seconds (configurable, or off).
- **Mouse wheel click** on the island or the notch hides it and the activity capsule, whatever plays. Bring it back with another wheel click in the same place, **⌃⌥⌘N** or "Show the island" in the menu.
- **⌃⌥⌘N** (configurable): expand or collapse the island on the screen under the pointer. Works even when paused media is hidden, so you can resume.
- Click the title to open the playing app. The progress bar looks like Apple's: white, no knob, thicker under the pointer and while held. Click or drag it to seek; pulled past an end it stretches a little. The new position holds until the player confirms it, so the bar does not jump back.
- "Back" after 3 seconds restarts the track. If the player has no next track (a single video in a browser), "forward" skips 15 s and both buttons switch to ±15 s.
- Hidden in full-screen apps by default.

## Look: island or notch

In Settings (**Island and notch → Look**) choose **Auto** (notch on a MacBook with a notch, a separate island on other screens), **Island** (a separate pill on any screen; on a MacBook with a notch it sits below the menu bar) or **Notch** (a shape hanging from the top edge; where there is no notch it is drawn at the top centre).

## Outline

Like the iPhone's island over a dark background: a thin light edge around the island, the notch and the activity capsule, so they do not disappear on a black wallpaper or a dark menu bar. On the notch it runs along the sides and the bottom only. Turn it off in Settings (**Island and notch → Thin outline**).

## Live activities

Like Dynamic Island: one activity at a time (more important wins), shown according to what else is on screen:

- **Next to music**: a small circle on the right of the island with only the timer ring or a glyph, no text. It comes out of the island's edge like a drop, with a liquid neck, and goes back in the same way when the activity ends.
- **Without music**: the activity becomes the island itself, glyph on the left, time on the right (beside the notch on a MacBook).
- **Click** the circle or that island to open its card: the ring, the big time and large ✕ and pause buttons, like the iPhone's timer. It closes when the pointer leaves it, or with another click.
- **Short notices** (charger, headphones), as on the iPhone: for 4 seconds the island stretches into a long pill of the same height. Headphones show the device glyph on the left (AirPods, AirPods Pro, AirPods Max, Beats, HomePod or a speaker, from its name) and the name on the right. Power shows "Charging", "On Battery" or "Low Battery" on the left and the charge with a battery in the event's colour on the right. On a notched MacBook each side sits beside the camera. It takes no clicks, and while the island is expanded the notice waits beside it as a circle instead of covering the buttons.

What is shown:

- **Timer** and **stopwatch**, started from the menu bar menu or from Settings. Pause and cancel with the buttons on the open card. A finished timer rings (the sound can be chosen or turned off in Settings) and goes away after 10 seconds.
- **Power**: charger plugged in or unplugged, battery down to a threshold (20 % by default, set in Settings).
- **Bluetooth headphones** became the sound output (shows the device name).
- **File progress** (off by default, experimental): copies and downloads, percent only.

Everything is local: no network, no new permissions, and every source has its own switch in Settings. Details in [SECURITY.md](SECURITY.md).

## Settings

The window works like System Settings: pages in a sidebar with search, an icon and an explanation on every row, and a Reset button on every page.

- **General**: open at login, the menu bar icon (without it, open Islet again to get the settings), the shortcut, the language, and the theme of windows and menus (system, light, dark).
- **Permissions**: what Islet uses (the Now Playing source, system audio recording for the bars) with the state of each, and what it never touches (network, keyboard, Bluetooth, files).
- **About**: version, privacy, licenses.
- **Island and notch**: a live preview, the look (Auto, Island, Notch) and the displays as pictures, the outline, full-screen apps, size and position.
- **Now Playing**: a preview of the expanded island, expand on hover with a delay, the collapse delay, expanding on a new track and for how long, hiding when paused, the title, colour from artwork, the equaliser mode.
- **Timer**: start a timer or the stopwatch, the alert sound with a preview.
- **Battery** and **Headphones**: which notices to show, the low battery threshold, how long a notice stays.
- **Downloads**: file copy and download progress.

## Build and run

Requires macOS 27 and the Command Line Tools (Xcode is optional). No paid developer account.

```bash
scripts/build-app.sh            # release → build/Islet.app
scripts/install.sh              # build and install into /Applications, replacing the old version
scripts/audit.sh                # security audit of the sources
swift test                      # core unit tests
scripts/test.sh                 # tests, app bundle and launch self-check
```

Install: `scripts/install.sh` builds the app, quits the running copy, moves the old version out of Applications into the Trash (so it can be put back), installs the new one and starts it. Settings are kept. By hand: drag `build/Islet.app` into Applications and open it. If a new copy starts while an old one is running, the old one quits by itself. The icon appears in the menu bar (there is no Dock icon). Settings are in that menu, or open Islet again from Finder.

Self-check: `build/Islet.app/Contents/MacOS/Islet --self-check` starts the app, prints the data source, current track, screens and islands, and exits with 0 (OK), 2 (works only in fallback mode) or 1 (broken). It waits for the adapter's own check, so a blocked MediaRemote cannot pass as OK.

### If macOS refuses to open it

The build has an ad-hoc signature, not a Developer ID. If you copied `Islet.app` from another Mac or downloaded an archive, macOS may call it damaged or unverified. Remove the quarantine flag:

```bash
xattr -cr /Applications/Islet.app
```

Then open it again (or right-click → Open). Quarantine also stops the system `perl` from loading the bundled adapter framework. Islet then falls back to Music/Spotify, and `xattr -cr` fixes that too.

### Permissions

- **The primary mode asks for nothing.** The global shortcut uses Carbon `RegisterEventHotKey` and needs no Accessibility access. Hovering is tracked without special rights.
- **Bars that follow the sound** ask for System Audio Recording (a Core Audio process tap). Islet only measures loudness per frequency band: nothing is recorded, stored or changed. If you declined, turn Islet on in Privacy & Security → Screen & System Audio Recording → System Audio Recording Only (Islet's settings have a button for it) and restart Islet. The ad-hoc signature changes with every rebuild, so macOS asks again after a rebuild.
- **Fallback mode** (below) controls Music and Spotify through AppleScript. The first time, macOS asks "Islet wants to control Music". Change it in System Settings → Privacy & Security → Automation.
- **Open at login** is in Islet's settings (`SMAppService`). If macOS asks for approval, it is in System Settings → General → Login Items.

## Where the data comes from

Since macOS 15.4 the private MediaRemote framework, which knows what is playing, only answers Apple software. Islet uses [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter): the system `/usr/bin/perl` is signed by Apple, so MediaRemote answers it. Perl loads a small bundled framework that prints JSON lines with every change (`stream`). Commands (pause, next, previous, seek) go the same way. All of it was verified on macOS 27.0.1: title, artist, artwork, state, duration, position, and play/pause/next/previous/seek.

**Fallback.** If the adapter does not start, crashes more than twice in a row, or its own check (`test`) reports MediaRemote as closed, Islet switches to Music and Spotify: their notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) plus AppleScript for position, artwork and control. It never launches a player. Settings show the switch in one line, with a Retry button.

The position is computed, not polled: `elapsed + rate × (now − timestamp)`. The view redraws 30 times a second only while the island is expanded and playing. Artwork is downscaled to 256 px; the last 20 are kept in memory.

## Privacy and resources

Details, permissions and how to report a vulnerability: [SECURITY.md](SECURITY.md).

- No telemetry, no analytics. The only network request is downloading Spotify artwork in fallback mode (Spotify provides it as a URL). Image only, no cookies, cached.
- About 0 % CPU when idle. Audio capture and analysis (1024-point FFT, Accelerate) run only while the island is visible and a track plays: about 1–2 % CPU. The bars are Core Animation layers. A hidden or paused island has no audio capture, no timers and no pointer tracking.
- No third-party dependencies apart from the bundled adapter.

## How it is built

| Part | Where |
|---|---|
| Window-free logic: adapter stream parsing, state machine, geometry, position interpolation, marquee, artwork colour, source failover, live activities (timer, stopwatch, queue, capsule placement) | `Sources/IsletCore` (+ tests) |
| Sources: adapter via `/usr/bin/perl`, Music/Spotify fallback | `Sources/Islet/Sources` |
| Panels (non-activating `NSPanel`, one per screen), pointer tracking, display changes | `Sources/Islet/Island` |
| SwiftUI island: notch shape with concave top corners, pill, spring animations, Core Animation equaliser | `Sources/Islet/Island` |
| Live activity sources: battery (IOKit), sound output (Core Audio), file progress (`Progress`) | `Sources/Islet/Activities` |
| Activity capsule beside the island; every animation in one place | `Sources/Islet/Island/SatelliteView.swift`, `IslandMotion.swift` |
| Menu bar item, settings, hotkey, login item | `Sources/Islet/Menu`, `Settings`, `System` |
| MediaRemote adapter (unmodified, BSD-3-Clause) | `Vendor/mediaremote-adapter`, built by `scripts/build-adapter.sh` |

The style is chosen per screen: a screen with a notch (`safeAreaInsets.top > 0`, notch width from `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`) gets the notch style, every other screen the pill. The "Look" setting can override that: "Island" everywhere (below the menu bar on a notched screen) or "Notch" everywhere (a compact drawn notch at the top centre where there is none). The layout is a pure function of screen descriptions and settings, recomputed when a monitor is plugged in, the lid closes or the resolution changes. On monitors the menu bar height comes from `frame` vs `visibleFrame`: on macOS 27 `NSStatusBar.system.thickness` returns 22 pt while the bar is 30 pt, so it is only the fallback for an auto-hidden menu bar.

Tests (Swift Testing, 154): JSON stream parsing (normal, empty, broken, split into chunks), every state-machine transition with an injected clock, frames for a notched screen, 1× and 2× monitors, two screens and configuration changes, interpolation, marquee, dominant colour on synthetic images, source failover, bars on synthetic tones (bass, mids, highs, silence), back/forward buttons, timer and stopwatch (pause, finish, limits), activity priorities, capsule placement in every look and scale, the drawn notch, seeking (the position holds until the player confirms it, the bar stretches past its ends). `scripts/audit.sh` checks the sources for network, program launch and permissions.

## Limitations

- The Perl route into MediaRemote may break in a future macOS. The fallback covers that, but only for Music and Spotify.
- At launch Islet runs the adapter's health check (`test`) once. If nothing is playing at that moment, it briefly creates an untitled "Now Playing" entry; the island ignores it.
- Browsers do not always provide artwork (YouTube in Safari, for example). The browser's icon is shown instead.
- The notch style was checked with renders and tests. Live testing on this Mac used a 1440p monitor (1×) with the MacBook lid closed.
- Headphones: only the device name is shown; the AirPods battery level is not read (that would need Bluetooth permission or a private API).
- File progress is experimental: only operations that an app reports through `Progress` are shown, and only in Downloads, Desktop, Documents and mounted volumes.
- `docs/overview.png` still shows the old numbers (5,900 lines, 95 tests).
- Ad-hoc signature. After a rebuild macOS may ask for Automation permission again. To distribute, sign with a Developer ID and notarize.

## Debugging

```bash
log stream --level info --predicate 'subsystem == "app.islet"'
build/Islet.app/Contents/MacOS/Islet --self-check
swift build && $(swift build --show-bin-path)/Islet --render-preview out/   # PNG of every state (debug builds only)
```

## License

MIT, see [LICENSE](LICENSE).

Bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) © 2025 Jonas van den Berg and contributors, BSD 3-Clause License, see [Vendor/mediaremote-adapter/LICENSE](Vendor/mediaremote-adapter/LICENSE). A copy also ships inside the app: `Contents/Resources/Licenses`.
