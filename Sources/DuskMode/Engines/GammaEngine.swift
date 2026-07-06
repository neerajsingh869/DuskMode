import AppKit
import CoreGraphics

/// Layer 1, primary path: colour temperature via display gamma tables — the same
/// public API f.lux itself uses (`CGSetDisplayTransferByFormula`). Gamma *multiplies*
/// every pixel, so blacks stay black and the result reads as warm light instead of a
/// translucent red film. It also never appears in screenshots and cannot flash during
/// Space/app switches, because it isn't a window at all.
///
/// The overlay tint (OverlayEngine) remains the automatic fallback: this API is broken
/// on the newest Apple Silicon (values store but aren't applied). On this machine
/// (M4, macOS 15) it was verified live before this engine was written. If a set call
/// ever fails, `isAvailable` flips false and AppDelegate routes warmth to the overlay.
///
/// Safety: the WindowServer restores gamma automatically when the owning process
/// exits, so even a crash can never leave the screen tinted.
final class GammaEngine {

    private(set) var isAvailable = true

    private var active = false
    private var warmth = 0.0

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(reapply),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reapplyAfterWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Returns true when the gamma path is handling colour (so the overlay shouldn't).
    @discardableResult
    func apply(enabled: Bool, warmth: Double) -> Bool {
        guard isAvailable else { return false }
        self.warmth = warmth
        let wasActive = active
        active = enabled && warmth > 0.001
        guard active else {
            if wasActive { CGDisplayRestoreColorSyncSettings() }
            return true
        }
        return setAllDisplays(ColorTemperature.multiplier(forWarmth: warmth))
    }

    /// Put the display back exactly as macOS expects. Call on app termination.
    func shutdown() {
        if active { CGDisplayRestoreColorSyncSettings() }
        active = false
    }

    // MARK: - Private

    @discardableResult
    private func setAllDisplays(_ m: (r: Double, g: Double, b: Double)) -> Bool {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &count) == .success, count > 0 else {
            isAvailable = false
            return false
        }
        var anySuccess = false
        for display in displays.prefix(Int(count)) {
            // Linear per-channel scale: min 0, max = multiplier, gamma 1 leaves the
            // display's own response curve intact and just attenuates green/blue.
            let err = CGSetDisplayTransferByFormula(
                display,
                0, CGGammaValue(m.r), 1,
                0, CGGammaValue(m.g), 1,
                0, CGGammaValue(m.b), 1)
            anySuccess = anySuccess || (err == .success)
        }
        if !anySuccess { isAvailable = false }
        return anySuccess
    }

    @objc private func reapply() {
        guard active else { return }
        setAllDisplays(ColorTemperature.multiplier(forWarmth: warmth))
    }

    @objc private func reapplyAfterWake() {
        guard active else { return }
        // Give the display pipeline a moment to settle after wake.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reapply()
        }
    }
}
