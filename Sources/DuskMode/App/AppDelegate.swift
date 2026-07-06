import AppKit
import DuskModeCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    let overlayEngine = OverlayEngine()
    let gammaEngine = GammaEngine()
    let grayscaleEngine = GrayscaleEngine()
    let circadianEngine = CircadianEngine()

    /// Last grayscale state the *schedule* asked for. Grayscale is only touched when
    /// this changes (edge-triggered): the macOS Colour Filters bezel would otherwise
    /// fire every 30s tick, and a manual grayscale toggle mid-phase would be fought.
    private var scheduledGrayscale: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        circadianEngine.onTarget = { [weak self] target in
            self?.applyScheduleTarget(target)
        }
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
            grayscaleEngine: grayscaleEngine,
            circadianEngine: circadianEngine)
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
        if prefs.scheduleEnabled {
            // The circadian schedule owns the screen: (re)start it and let its
            // target flow through applyScheduleTarget. Manual values are ignored.
            circadianEngine.setEnabled(true)
        } else {
            if circadianEngine.isEnabled {
                circadianEngine.setEnabled(false)
                scheduledGrayscale = nil   // schedule no longer owns grayscale
            }
            applyManual(prefs)
        }
    }

    /// The Phase-1 manual path: master switch + sliders.
    private func applyManual(_ prefs: PreferencesStore) {
        // Gamma carries BOTH colour and dim whenever it works: it isn't a window, so
        // it can never flash during app switches (REGRESSIONS.md #9). Only when gamma
        // is unavailable (newest-Apple-Silicon regression) does the overlay window
        // exist at all, carrying both layers with the same blackbody hue.
        let gammaHandlesFilters = gammaEngine.apply(enabled: prefs.masterEnabled,
                                                    warmth: prefs.warmth,
                                                    dim: prefs.dim)
        overlayEngine.apply(enabled: prefs.masterEnabled && !gammaHandlesFilters,
                            warmth: prefs.warmth,
                            dim: prefs.dim)
    }

    /// The Phase-2 automatic path: same engines, values from the timeline.
    private func applyScheduleTarget(_ target: CircadianTimeline.Target) {
        let gammaHandlesFilters = gammaEngine.apply(enabled: target.active,
                                                    warmth: target.warmth,
                                                    dim: target.dim)
        overlayEngine.apply(enabled: target.active && !gammaHandlesFilters,
                            warmth: target.warmth,
                            dim: target.dim)
        if scheduledGrayscale != target.grayscale {
            if grayscaleEngine.isGrayscaleEnabled() != target.grayscale {
                grayscaleEngine.setGrayscale(target.grayscale)
            }
            scheduledGrayscale = target.grayscale
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave the screen exactly as macOS expects: gamma restored, colour back on.
        gammaEngine.shutdown()
        grayscaleEngine.shutdown()
    }
}
