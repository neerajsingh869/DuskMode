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

    /// Whether the gamma pipeline is usable on this machine. Determined ONCE at
    /// startup and NEVER revoked by transient runtime failures.
    ///
    /// REGRESSION GUARD (REGRESSIONS.md #10): a `CGSetDisplayTransferByFormula` call
    /// can fail harmlessly for a moment when the display is asleep or mid-reconfig
    /// (lid close/open, monitor hot-plug). The old code latched `isAvailable = false`
    /// on the first such failure and silently dropped the ENTIRE app onto the inferior
    /// overlay for the rest of the session — muddy color + app-switch flash, with no
    /// recovery. Gamma actually works fine on this M4; it was the latch that broke it.
    /// Now we skip the failed cycle and reassert on the next event; gamma stays THE path.
    private(set) var isAvailable: Bool

    /// Deepest allowed gamma dim — always leaves ≥8% output so the screen can never
    /// become unusable. Mirrors OverlayEngine.maxDimAlpha.
    private let maxDimScale = 0.92

    private var active = false
    private var warmth = 0.0
    private var dim = 0.0

    init() {
        isAvailable = GammaEngine.probeCapability()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reapply),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reapplyAfterWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// Returns true when the gamma path is handling colour+dim (so the overlay shouldn't).
    /// This reflects the machine's fixed capability, NOT whether this single set call
    /// happened to land — a transient failure (display asleep) must not hand the frame
    /// to the overlay, or the app-switch flash comes back for that cycle.
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
        setAllDisplays(currentMultiplier())   // may transiently fail; retried on next event
        return true                           // gamma remains THE path either way
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

    /// One-time capability probe. Confirms the gamma API path is wired up on this
    /// machine (display list + a formula set both accepted). It CANNOT detect the
    /// "stores but never applies" newest-Apple-Silicon regression — that returns
    /// success too — but on hardware where the API is genuinely dead the set call
    /// errors out, and we fall back to the overlay. If the display isn't ready at
    /// launch, assume capable rather than punishing gamma for the whole session.
    private static func probeCapability() -> Bool {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &count) == .success, count > 0 else {
            return true
        }
        let err = CGSetDisplayTransferByFormula(displays[0], 0, 1, 1, 0, 1, 1, 0, 1, 1)
        return err == .success
    }

    /// Push the current multiplier to every display. Returns whether at least one set
    /// landed, for logging only — a transient failure (display asleep / reconfiguring)
    /// must NOT flip `isAvailable`; the next screen-param or wake event reasserts it.
    @discardableResult
    private func setAllDisplays(_ m: (r: Double, g: Double, b: Double)) -> Bool {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &count) == .success, count > 0 else {
            return false   // display not ready — skip this cycle, do not latch
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
        return anySuccess
    }

    @objc private func reapply() {
        guard active else { return }
        setAllDisplays(currentMultiplier())
    }

    @objc private func reapplyAfterWake() {
        guard active else { return }
        // WindowServer can reset gamma to identity across sleep, and the display may
        // come back gradually — a single attempt can land before it's ready and then
        // never retry (nothing reasserts in manual mode). Retry over a few seconds so
        // the tint reliably returns after lid open. (REGRESSIONS.md #10.)
        for delay in [0.3, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reapply()
            }
        }
    }
}
