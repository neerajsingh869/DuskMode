import AppKit
import DuskModeCore

/// Layer 1 (color/melatonin) + Layer 3 (dimming/cortisol) — FALLBACK path only.
///
/// GammaEngine carries both colour and dim on working hardware, because gamma isn't
/// a window and therefore can never flash during app/Space switches (REGRESSIONS.md
/// #1/#9). This engine only engages when the gamma API is broken (newest Apple
/// Silicon): a transparent, click-through NSWindow over every screen with a single
/// tint+dim colour baked in. Plain AppKit, unchanged for ~20 years.
///
/// Warmth pushes the tint from amber toward deep red (blue+green suppression, red-shift).
/// Dim adds darkening beyond the hardware brightness floor (~6 lux halves melatonin — see
/// research/notes.md), which the science says matters *more* than colour alone.
final class OverlayEngine {

    // Tunables. maxDimAlpha caps how dark we let the overlay go so the screen never
    // becomes fully unusable; spec allows up to ~95%.
    private let maxTintAlpha: CGFloat = 0.60
    private let maxDimAlpha: CGFloat = 0.92

    private var windows: [OverlayWindow] = []
    private var active = false
    private var lastWarmth = 0.0
    private var lastDim = 0.0

    init() {
        let nc = NotificationCenter.default
        // Rebuild overlays when displays are connected/disconnected/rearranged.
        nc.addObserver(self, selector: #selector(rebuild),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let wsnc = NSWorkspace.shared.notificationCenter
        // Reassert after the machine wakes — overlays can be dropped across sleep.
        wsnc.addObserver(self, selector: #selector(reassert),
                         name: NSWorkspace.didWakeNotification, object: nil)
        // Re-front only on Space transitions (which are animated, so a reorder is
        // invisible). NOTE: there was previously a didActivateApplication observer
        // doing the same on every ⌘Tab — that reorder itself caused a split-second
        // overlay dropout, so it must not come back. collectionBehavior already
        // keeps the window on all Spaces and above everything at .screenSaver level.
        wsnc.addObserver(self, selector: #selector(reorderFront),
                         name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    // MARK: - Public control

    /// Turn the overlay on with the given warmth/dim, or off entirely.
    /// Warmth is 0 whenever GammaEngine is carrying the colour layer.
    ///
    /// REGRESSION GUARD (see REGRESSIONS.md #1): this is called every 30 s by the
    /// circadian schedule, so it must be idempotent at the window-server level.
    /// Re-ordering an already-visible overlay is what causes the one-frame ⌘Tab
    /// flash — order front only on first show, and only touch the colour when it
    /// actually changed. The window stays alive (possibly fully transparent) while
    /// enabled, so ramps crossing dim=0 never create/destroy windows mid-session.
    func apply(enabled: Bool, warmth: Double, dim: Double) {
        lastWarmth = warmth
        lastDim = dim
        active = enabled
        guard enabled else { teardown(); return }
        let color = Self.overlayColor(warmth: CGFloat(warmth), dim: CGFloat(dim),
                                      maxTintAlpha: maxTintAlpha, maxDimAlpha: maxDimAlpha)
        if windows.isEmpty { buildWindows() }
        for w in windows {
            w.setOverlayColor(color)
            if !w.isVisible { w.orderFrontRegardless() }
        }
    }

    // MARK: - Window lifecycle

    private func buildWindows() {
        teardown()
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
    }

    private func teardown() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }

    /// Lightweight: just push existing overlays back to the front (no rebuild).
    /// Used on Space/app switches to eliminate the momentary flash of un-tinted screen.
    @objc private func reorderFront() {
        guard active else { return }
        for w in windows { w.orderFrontRegardless() }
    }

    @objc private func rebuild() {
        guard active else { return }
        buildWindows()
        // Use the values from the last apply(), NOT PreferencesStore: when gamma is
        // handling colour, the applied warmth is 0 even though prefs.warmth isn't.
        apply(enabled: true, warmth: lastWarmth, dim: lastDim)
    }

    @objc private func reassert() {
        guard active else { return }
        // Give the display system a moment to settle after wake, then re-show.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.rebuild()
        }
    }

    // MARK: - Colour maths

    /// Collapse a warm tint (alpha a1) composited over a black dim (alpha a2) into a
    /// single equivalent RGBA, so we only need one overlay window per screen.
    ///
    /// The tint targets the same blackbody multiplier the gamma engine would apply at
    /// this warmth. Source-over compositing can't truly multiply, so we pick the
    /// alpha + colour pair that reproduces the multiplier exactly on white content
    /// (a1 = 1 - min(multiplier); tint = (multiplier - (1-a1)) / a1), capped at
    /// maxTintAlpha so dark content isn't washed out.
    ///
    /// Compositing tint over background B then black over that yields:
    ///   result = (B*(1-a1) + tint*a1) * (1-a2)
    /// A single colour C at alpha A over B gives B*(1-A) + C*A. Matching terms:
    ///   A = 1 - (1-a1)(1-a2)
    ///   C = tint * a1 * (1-a2) / A
    static func overlayColor(warmth: CGFloat, dim: CGFloat,
                             maxTintAlpha: CGFloat, maxDimAlpha: CGFloat) -> NSColor {
        let w = clamp01(warmth)
        let d = clamp01(dim)

        let m = ColorTemperature.multiplier(forWarmth: Double(w))
        let aNeeded = 1 - CGFloat(min(m.g, m.b))
        let a1 = w > 0.001 ? min(aNeeded, maxTintAlpha) : 0
        var tint = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
        if a1 > 0.0001 {
            tint.r = clamp01((CGFloat(m.r) - (1 - a1)) / a1)
            tint.g = clamp01((CGFloat(m.g) - (1 - a1)) / a1)
            tint.b = clamp01((CGFloat(m.b) - (1 - a1)) / a1)
        }

        let a2 = d * maxDimAlpha            // strength of the darkening
        let a = 1 - (1 - a1) * (1 - a2)     // combined alpha

        guard a > 0.0001 else {
            return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        }
        let scale = a1 * (1 - a2) / a       // tint contribution after darkening
        return NSColor(srgbRed: tint.r * scale,
                       green: tint.g * scale,
                       blue: tint.b * scale,
                       alpha: a)
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }
}

/// A single borderless, click-through overlay covering one screen.
private final class OverlayWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true          // clicks pass straight through
        backgroundColor = .clear
        level = .screenSaver               // above normal windows and the menu bar
        animationBehavior = .none          // no fade in/out — a fade reads as a flash
        // Cover every Space and stay put; also float over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: true)
    }

    private var currentColor: NSColor?

    func setOverlayColor(_ color: NSColor) {
        guard color != currentColor else { return }   // skip no-op invalidations
        currentColor = color
        backgroundColor = color
    }

    // Borderless windows can't become key/main by default; keep it that way so the
    // overlay never steals focus or keyboard input.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
