import AppKit
import ApplicationServices
import notify

/// The minimal grayscale surface AppDelegate depends on. Extracted so a recording
/// double can be injected in tests/verification without toggling real system grayscale
/// (no bezels, no screen change). `GrayscaleEngine` is the production implementation.
protocol GrayscaleControlling: AnyObject {
    func isGrayscaleEnabled() -> Bool
    func setGrayscale(_ enabled: Bool)
    func shutdown()
}

/// Layer 2 (dopamine/compulsion interruption): system-wide grayscale, one tap, no setup.
///
/// Primary method: `UAGrayscaleSetEnabled` / `UAGrayscaleIsEnabled` (UniversalAccess,
/// private, dlsym-loaded) — the switch the Accessibility settings pane itself uses.
/// Instant, no Accessibility permission, nothing manual for the user.
///
/// THE BEZEL IS UNAVOIDABLE — do not try to remove it again. macOS shows its
/// "Colour Filters On/Off" HUD on every toggle because AccessibilityVisualsAgent
/// watches the preference store itself, not any notification we could skip.
/// Exhaustively verified live on macOS 15.7.3 (2026-07-06): CGDisplayForceToGray
/// sets its flag but no longer renders; SkyLight's SLSAddWindowFilter whitelist
/// rejects every desaturation CIFilter (only CIColorInvert is allowed); gamma
/// tables can't mix channels; and writing the MediaAccessibility pref without
/// notify_post still triggers the bezel. Neeraj accepted the bezel (2026-07-06).
///
/// Fallback 1: write the MediaAccessibility pref directly + notify (same effect,
/// used only if the UA symbols ever disappear). Fallback 2: synthesise the Color
/// Filters shortcut (⌥⌘F5) via public CGEvent. Degrades, never crashes.
final class GrayscaleEngine: GrayscaleControlling {

    private typealias SetBoolFn = @convention(c) (Bool) -> Void
    private typealias GetBoolFn = @convention(c) () -> Bool
    private typealias MASetFn = @convention(c) (Int64, Bool) -> Void
    private typealias MAGetFn = @convention(c) (Int64) -> Int64

    // Primary: UniversalAccess.
    private var uaSetGray: SetBoolFn?
    private var uaGetGray: GetBoolFn?

    // Fallback 1: MediaAccessibility display-filter pref (category 1 = Color Filters).
    private var maSetEnabled: MASetFn?
    private var maGetEnabled: MAGetFn?
    private let maColorFilterCategory: Int64 = 1

    /// F5 keycode, for the last-resort CGEvent fallback only.
    private let kVK_F5: CGKeyCode = 0x60

    init() {
        loadSymbols()
    }

    /// True when an instant, no-permission method is available.
    var isSupported: Bool { uaSetGray != nil || maSetEnabled != nil }

    /// Best-effort read of the current system grayscale state.
    func isGrayscaleEnabled() -> Bool {
        if let read = uaGetGray { return read() }
        if let read = maGetEnabled { return read(maColorFilterCategory) != 0 }
        return PreferencesStore.shared.grayscaleOn
    }

    /// Turn grayscale on or off.
    func setGrayscale(_ enabled: Bool) {
        if let write = uaSetGray {
            write(enabled)
        } else if let write = maSetEnabled {
            write(maColorFilterCategory, enabled)
            notify_post("com.apple.mediaaccessibility.displayFilterSettingsChanged")
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

    /// The app's effects end with the app: colour comes back on quit, matching the
    /// gamma and overlay layers (which the OS reverts automatically).
    func shutdown() {
        if isGrayscaleEnabled() {
            setGrayscale(false)
        }
    }

    // MARK: - Private symbol loading

    private func loadSymbols() {
        let uaPath = "/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess"
        if let ua = dlopen(uaPath, RTLD_NOW) {
            if let sym = dlsym(ua, "UAGrayscaleSetEnabled") {
                uaSetGray = unsafeBitCast(sym, to: SetBoolFn.self)
            }
            if let sym = dlsym(ua, "UAGrayscaleIsEnabled") {
                uaGetGray = unsafeBitCast(sym, to: GetBoolFn.self)
            }
        }
        let maPath = "/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility"
        if let ma = dlopen(maPath, RTLD_NOW) {
            if let sym = dlsym(ma, "MADisplayFilterPrefSetCategoryEnabled") {
                maSetEnabled = unsafeBitCast(sym, to: MASetFn.self)
            }
            if let sym = dlsym(ma, "MADisplayFilterPrefGetCategoryEnabled") {
                maGetEnabled = unsafeBitCast(sym, to: MAGetFn.self)
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
