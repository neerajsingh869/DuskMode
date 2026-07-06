import AppKit

/// Layer 1 (color/melatonin) + Layer 3 (dimming/cortisol) in one engine.
///
/// This is the app's unbreakable foundation. Instead of the gamma-table API
/// (public but currently broken on newest Apple Silicon, and it fights Night Shift),
/// we lay a transparent, click-through NSWindow over every screen and bake a single
/// tint+dim colour into it. Plain AppKit, unchanged for ~20 years.
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

    init() {
        let nc = NotificationCenter.default
        // Rebuild overlays when displays are connected/disconnected/rearranged.
        nc.addObserver(self, selector: #selector(rebuild),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Reassert after the machine wakes — overlays can be dropped across sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reassert),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: - Public control

    /// Turn the overlay on with the given warmth/dim, or off entirely.
    func apply(enabled: Bool, warmth: Double, dim: Double) {
        active = enabled
        guard enabled else { teardown(); return }
        if windows.isEmpty { buildWindows() }
        let color = Self.overlayColor(warmth: CGFloat(warmth), dim: CGFloat(dim),
                                      maxTintAlpha: maxTintAlpha, maxDimAlpha: maxDimAlpha)
        for w in windows {
            w.setOverlayColor(color)
            w.orderFrontRegardless()
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

    @objc private func rebuild() {
        guard active else { return }
        buildWindows()
        apply(enabled: true,
              warmth: PreferencesStore.shared.warmth,
              dim: PreferencesStore.shared.dim)
    }

    @objc private func reassert() {
        guard active else { return }
        // Give the display system a moment to settle after wake, then re-show.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.rebuild()
        }
    }

    // MARK: - Colour maths

    /// Collapse an amber→red tint (alpha a1) composited over a black dim (alpha a2)
    /// into a single equivalent RGBA, so we only need one overlay window per screen.
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

        // Tint hue: amber at low warmth → deep red at high warmth.
        let amber = (r: CGFloat(1.0), g: CGFloat(0.60), b: CGFloat(0.25))
        let deepRed = (r: CGFloat(1.0), g: CGFloat(0.15), b: CGFloat(0.05))
        let tint = (r: lerp(amber.r, deepRed.r, w),
                    g: lerp(amber.g, deepRed.g, w),
                    b: lerp(amber.b, deepRed.b, w))

        let a1 = w * maxTintAlpha           // strength of the colour wash
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
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
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
        // Cover every Space and stay put; also float over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: true)
    }

    func setOverlayColor(_ color: NSColor) {
        backgroundColor = color
    }

    // Borderless windows can't become key/main by default; keep it that way so the
    // overlay never steals focus or keyboard input.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
