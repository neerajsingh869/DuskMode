import AppKit
import CoreGraphics
import DuskModeCore

/// Layer 1 (colour) AND Layer 3 (dimming), primary path: display gamma tables — the
/// same public API f.lux itself uses (`CGSetDisplayTransferByFormula`). Gamma
/// *multiplies* every pixel, so blacks stay black and the result reads as warm light
/// instead of a translucent red film. Dimming is folded in by scaling all three
/// channels down — mathematically identical to a black overlay, but it isn't a window,
/// so it can never flash during app/Space switches (REGRESSIONS.md #9) and never
/// appears in screenshots.
///
/// The overlay (OverlayEngine) remains the automatic full fallback: this API is broken
/// on the newest Apple Silicon (values store but aren't applied). On this machine
/// (M4, macOS 15) it was verified live before this engine was written. If a set call
/// ever fails, `isAvailable` flips false and AppDelegate routes both warmth and dim
/// to the overlay.
///
/// Safety: the WindowServer restores gamma automatically when the owning process
/// exits, so even a crash can never leave the screen tinted or dimmed.
final class GammaEngine {

    private(set) var isAvailable = true

    /// Deepest allowed gamma dim — always leaves ≥8% output so the screen can never
    /// become unusable. Mirrors OverlayEngine.maxDimAlpha.
    private let maxDimScale = 0.92

    private var active = false
    private var warmth = 0.0
    private var dim = 0.0

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(reapply),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reapplyAfterWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Returns true when the gamma path is handling colour+dim (so the overlay shouldn't).
    @discardableResult
    func apply(enabled: Bool, warmth: Double, dim: Double) -> Bool {
        guard isAvailable else { return false }
        self.warmth = warmth
        self.dim = dim
        let wasActive = active
        active = enabled && (warmth > 0.001 || dim > 0.001)
        guard active else {
            if wasActive { CGDisplayRestoreColorSyncSettings() }
            return true
        }
        return setAllDisplays(currentMultiplier())
    }

    /// Blackbody warmth multipliers scaled by the dim factor (all channels equally,
    /// so dimming never shifts the hue).
    private func currentMultiplier() -> (r: Double, g: Double, b: Double) {
        let m = ColorTemperature.multiplier(forWarmth: warmth)
        let s = 1 - min(1, max(0, dim)) * maxDimScale
        return (m.r * s, m.g * s, m.b * s)
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
        setAllDisplays(currentMultiplier())
    }

    @objc private func reapplyAfterWake() {
        guard active else { return }
        // Give the display pipeline a moment to settle after wake.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reapply()
        }
    }
}
