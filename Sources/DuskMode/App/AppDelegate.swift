import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    let overlayEngine = OverlayEngine()
    let gammaEngine = GammaEngine()
    let grayscaleEngine = GrayscaleEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: PreferencesStore.didChange, object: nil)

        // Reflect any persisted state on launch.
        preferencesChanged()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.stars.fill",
                                   accessibilityDescription: "DuskMode")
            button.image?.isTemplate = true   // adapts to light/dark menu bar
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentViewController = PopoverViewController(
            overlayEngine: overlayEngine,
            grayscaleEngine: grayscaleEngine)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Reacting to preference changes

    @objc private func preferencesChanged() {
        let prefs = PreferencesStore.shared
        // Gamma multiplies pixels (true warm light — blacks stay black, f.lux-quality),
        // so it carries the colour layer whenever it works; the overlay then only
        // carries sub-hardware dimming. If gamma is unavailable (newest-Apple-Silicon
        // regression), the overlay carries both, with the same blackbody hue.
        let gammaHandlesColor = gammaEngine.apply(enabled: prefs.masterEnabled,
                                                  warmth: prefs.warmth)
        overlayEngine.apply(enabled: prefs.masterEnabled,
                            warmth: gammaHandlesColor ? 0 : prefs.warmth,
                            dim: prefs.dim)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave the screen exactly as macOS expects: gamma restored, colour back on.
        gammaEngine.shutdown()
        grayscaleEngine.shutdown()
    }
}
