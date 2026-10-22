import AppKit
import IsletCore

/// Reads `NSScreen` into plain ``ScreenDescriptor`` values for the layout engine.
enum ScreenReader {
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func id(of screen: NSScreen) -> String {
        guard let display = displayID(of: screen) else { return screen.localizedName }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
           let text = CFUUIDCreateString(nil, uuid) as String? {
            return text
        }
        return String(display)
    }

    static func descriptors() -> [ScreenDescriptor] {
        let screens = NSScreen.screens
        let thickness = NSStatusBar.system.thickness
        return screens.enumerated().map { index, screen in
            let display = displayID(of: screen)
            return ScreenDescriptor(
                id: id(of: screen),
                frame: screen.frame,
                backingScale: screen.backingScaleFactor,
                safeAreaTop: screen.safeAreaInsets.top,
                auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
                auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
                isBuiltIn: display.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
                // The first screen carries the menu bar ("primary display" in System Settings).
                isMain: index == 0,
                statusBarThickness: thickness,
                visibleTopInset: max(0, screen.frame.maxY - screen.visibleFrame.maxY))
        }
    }

    static func screen(withID id: String) -> NSScreen? {
        NSScreen.screens.first { Self.id(of: $0) == id }
    }
}
