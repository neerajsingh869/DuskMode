import AppKit
import ApplicationServices

/// Layer 2 (dopamine/compulsion interruption): system-wide grayscale, one tap, no setup.
///
/// Primary method: `CGDisplayForceToGray` / `CGDisplayUsesForceToGray` — the
/// WindowServer's own force-to-gray switch (the one loginwindow uses). Instant, needs
/// no Accessibility permission, and crucially it does NOT route through the
/// Color Filters accessibility feature, so macOS shows no "Colour Filters On/Off"
/// HUD bezel. (The previous UAGrayscaleSetEnabled method triggered that bezel on
/// every toggle — bad UX.) Private symbols, so they're quarantined here and loaded
/// with dlsym; both verified present on macOS 15.7.3.
///
/// Fallback 1: `UAGrayscaleSetEnabled` (UniversalAccess) — works, but flashes the
/// system bezel. Fallback 2: synthesise the Color Filters shortcut (⌥⌘F5) via public
/// CGEvent. The app degrades gracefully, it never crashes.
final class GrayscaleEngine {

    private typealias SetBoolFn = @convention(c) (Bool) -> Void
    private typealias GetBoolFn = @convention(c) () -> Bool

    // Primary: CoreGraphics force-to-gray (no HUD).
    private var cgSetGray: SetBoolFn?
    private var cgGetGray: GetBoolFn?

    // Fallback 1: UniversalAccess (shows the system bezel).
    private var uaSetGray: SetBoolFn?
    private var uaGetGray: GetBoolFn?

    /// F5 keycode, for the last-resort CGEvent fallback only.
    private let kVK_F5: CGKeyCode = 0x60

    init() {
        loadSymbols()
    }

    /// True when a silent, instant, no-permission method is available.
    var isSupported: Bool { cgSetGray != nil || uaSetGray != nil }

    /// Best-effort read of the current system grayscale state.
    func isGrayscaleEnabled() -> Bool {
        if let read = cgGetGray { return read() }
        if let read = uaGetGray { return read() }
        return PreferencesStore.shared.grayscaleOn
    }

    /// Turn grayscale on or off.
    func setGrayscale(_ enabled: Bool) {
        if let write = cgSetGray {
            write(enabled)
        } else if let write = uaSetGray {
            write(enabled)
        } else {
            postColorFilterShortcut()
        }
        PreferencesStore.shared.grayscaleOn = enabled
    }

    /// Flip grayscale; returns the new state.
    @discardableResult
    func toggle() -> Bool {
        let newState = !isGrayscaleEnabled()
        setGrayscale(newState)
        return newState
    }

    /// Force-to-gray isn't visible in any Settings pane, so if the app quits while
    /// it's on the user would have no way to turn it off. Always leave colour on.
    func shutdown() {
        if let write = cgSetGray, let read = cgGetGray, read() {
            write(false)
        }
    }

    // MARK: - Private symbol loading

    private func loadSymbols() {
        if let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW) {
            if let sym = dlsym(cg, "CGDisplayForceToGray") {
                cgSetGray = unsafeBitCast(sym, to: SetBoolFn.self)
            }
            if let sym = dlsym(cg, "CGDisplayUsesForceToGray") {
                cgGetGray = unsafeBitCast(sym, to: GetBoolFn.self)
            }
        }
        let uaPath = "/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess"
        if let ua = dlopen(uaPath, RTLD_NOW) {
            if let sym = dlsym(ua, "UAGrayscaleSetEnabled") {
                uaSetGray = unsafeBitCast(sym, to: SetBoolFn.self)
            }
            if let sym = dlsym(ua, "UAGrayscaleIsEnabled") {
                uaGetGray = unsafeBitCast(sym, to: GetBoolFn.self)
            }
        }
        // Intentionally keep both handles open for the process lifetime.
    }

    // MARK: - Public last-resort fallback

    private func postColorFilterShortcut() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let flags: CGEventFlags = [.maskCommand, .maskAlternate]
        if let down = CGEvent(keyboardEventSource: src, virtualKey: kVK_F5, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: kVK_F5, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }
}
