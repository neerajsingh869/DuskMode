import AppKit
import ApplicationServices

/// Layer 2 (dopamine/compulsion interruption): system-wide grayscale, one tap, no setup.
///
/// Primary method: Apple's own grayscale switch, `UAGrayscaleSetEnabled` /
/// `UAGrayscaleIsEnabled` in the UniversalAccess framework, loaded at runtime with dlopen.
/// This is the switch the Accessibility settings pane itself uses — it applies instantly,
/// needs NO Accessibility permission, and requires nothing from the user. It's a non-public
/// symbol, so we isolate it entirely here and keep a public fallback (below) in case a future
/// macOS ever removes it — the app degrades, it never crashes.
///
/// Fallback: synthesise the Color Filters shortcut via public CGEvent. Used only if the
/// primary symbol can't be loaded.
final class GrayscaleEngine {

    private typealias SetEnabledFn = @convention(c) (Bool) -> Void
    private typealias IsEnabledFn  = @convention(c) () -> Bool

    private var setEnabledFn: SetEnabledFn?
    private var isEnabledFn: IsEnabledFn?

    /// F5 keycode, for the fallback path only.
    private let kVK_F5: CGKeyCode = 0x60

    init() {
        loadUniversalAccess()
    }

    /// True when the primary (instant, no-permission) method is available.
    var isSupported: Bool { setEnabledFn != nil }

    /// Best-effort read of the current system grayscale state.
    func isGrayscaleEnabled() -> Bool {
        if let read = isEnabledFn { return read() }
        return PreferencesStore.shared.grayscaleOn
    }

    /// Turn grayscale on or off.
    func setGrayscale(_ enabled: Bool) {
        if let write = setEnabledFn {
            write(enabled)
        } else {
            postColorFilterShortcut()   // fallback: flips whatever Color Filters is bound to
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

    // MARK: - Private symbol loading

    private func loadUniversalAccess() {
        let path = "/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        if let sym = dlsym(handle, "UAGrayscaleSetEnabled") {
            setEnabledFn = unsafeBitCast(sym, to: SetEnabledFn.self)
        }
        if let sym = dlsym(handle, "UAGrayscaleIsEnabled") {
            isEnabledFn = unsafeBitCast(sym, to: IsEnabledFn.self)
        }
        // Intentionally keep the handle open for the process lifetime.
    }

    // MARK: - Public fallback (only if the primary symbol is unavailable)

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
