import AppKit
import ApplicationServices

/// Layer 2 (dopamine/compulsion interruption): system-wide grayscale.
///
/// Design constraint (project rule #2): NO private APIs. The obvious route,
/// `UAGrayscaleSetEnabled` in the private UniversalAccess framework, is off-limits
/// because it can break on OS updates. Instead we drive Apple's OWN built-in
/// "Color Filters" toggle by synthesising its default keyboard shortcut (⌥⌘F5)
/// with the public CGEvent API. Apple maintains the grayscale itself; we just flip it.
///
/// Requirement: the user must (a) grant Accessibility permission to NightFlow, and
/// (b) have Color Filters set to Grayscale in System Settings. Onboarding (Phase 4)
/// will walk them through both. Until then this fails gracefully.
final class GrayscaleEngine {

    /// Virtual keycode for F5. The system default Color Filters shortcut is ⌥⌘F5.
    private let kVK_F5: CGKeyCode = 0x60

    /// True if NightFlow is trusted for Accessibility (needed to post system shortcuts).
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Ask the system to prompt the user for Accessibility permission (non-blocking).
    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Flip the system grayscale on/off by posting ⌥⌘F5.
    /// Returns false if we lack permission (caller can then prompt / guide the user).
    @discardableResult
    func toggle() -> Bool {
        guard hasAccessibilityPermission else { return false }
        postColorFilterShortcut()
        PreferencesStore.shared.grayscaleOn.toggle()
        return true
    }

    /// Open System Settings straight to Accessibility → Display, where Color Filters lives.
    func openColorFilterSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display",
            "x-apple.systempreferences:com.apple.preference.universalaccess"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Private

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
