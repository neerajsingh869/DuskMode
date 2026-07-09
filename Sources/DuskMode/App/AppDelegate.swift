import AppKit
import Carbon.HIToolbox
import DuskModeCore

/// Small surface the popover uses to drive Emergency Color without knowing about
/// the whole AppDelegate.
protocol EmergencyColorControlling: AnyObject {
    var isEmergencyColorActive: Bool { get }
    var emergencyColorEndDate: Date? { get }
    /// True only when there's actually a filter to suspend (colour/dim on via manual
    /// or an active schedule, or grayscale on). The button/hotkey are no-ops otherwise.
    var isEmergencyColorAvailable: Bool { get }
    func toggleEmergencyColor()
}

final class AppDelegate: NSObject, NSApplicationDelegate, EmergencyColorControlling {

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

    // MARK: Emergency Color (Phase 3)
    /// A momentary "I need real colours NOW" override that suspends every filter for
    /// a fixed window, then auto-reverts to whatever mode was running (manual or
    /// schedule). Sits ABOVE both apply paths via `applyEffectiveState`.
    static let emergencyColorChanged = Notification.Name("DuskMode.EmergencyColorChanged")
    static let emergencyColorDuration: TimeInterval = 60
    private var emergencyColorTimer: Timer?
    private(set) var emergencyColorEndDate: Date?
    private var grayscaleBeforeEmergency = false
    private var emergencyHotKey: GlobalHotKey?

    var isEmergencyColorActive: Bool { emergencyColorEndDate != nil }

    /// Something is currently filtering the screen, so there's a point to Emergency
    /// Color: colour/dim on (manual master, or an active schedule) OR grayscale on.
    var isEmergencyColorAvailable: Bool {
        let prefs = PreferencesStore.shared
        let colourActive = prefs.scheduleEnabled
            ? circadianEngine.currentTarget.active
            : prefs.masterEnabled
        return colourActive || grayscaleEngine.isGrayscaleEnabled()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        // Every tick re-evaluates through the single choke point so an active
        // Emergency Color override always wins over the schedule.
        circadianEngine.onTarget = { [weak self] _ in
            self?.applyEffectiveState()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: PreferencesStore.didChange, object: nil)

        // Global shortcut → Emergency Color. Public Carbon hotkey (⌥⌘C), no
        // Accessibility permission needed. Nil if the combo is already taken.
        emergencyHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_C),
                                       modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleEmergencyColor()
        }

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
            circadianEngine: circadianEngine,
            emergencyController: self)
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
            // The circadian schedule owns the screen: (re)start it. Its target flows
            // through onTarget → applyEffectiveState. Manual values are ignored.
            circadianEngine.setEnabled(true)
        } else {
            if circadianEngine.isEnabled {
                circadianEngine.setEnabled(false)
                scheduledGrayscale = nil   // schedule no longer owns grayscale
            }
        }
        applyEffectiveState()
    }

    // MARK: - Apply choke point

    /// The single place the screen state is decided. Emergency Color overrides
    /// everything; otherwise the schedule (if on) or the manual sliders drive.
    private func applyEffectiveState() {
        if isEmergencyColorActive {
            // Full colour: no gamma tint, no dim. Grayscale is handled once on the
            // activate/cancel transitions (below), NOT here — so the 30s schedule
            // tick can't re-toggle it and spam the bezel.
            _ = gammaEngine.apply(enabled: false, warmth: 0, dim: 0)
            overlayEngine.apply(enabled: false, warmth: 0, dim: 0)
            return
        }
        let prefs = PreferencesStore.shared
        if prefs.scheduleEnabled {
            applyScheduleTarget(circadianEngine.currentTarget)
        } else {
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

    // MARK: - Emergency Color

    func toggleEmergencyColor() {
        if isEmergencyColorActive { cancelEmergencyColor() }
        else if isEmergencyColorAvailable { activateEmergencyColor() }
        // Nothing filtered → nothing to suspend; button/hotkey do nothing.
    }

    func activateEmergencyColor(seconds: TimeInterval = AppDelegate.emergencyColorDuration) {
        let firstActivation = !isEmergencyColorActive
        // Mark active FIRST so any change notification (e.g. from dropping grayscale
        // below) already resolves through the emergency branch.
        emergencyColorEndDate = Date().addingTimeInterval(seconds)
        emergencyColorTimer?.invalidate()
        let t = Timer(timeInterval: seconds, target: self,
                      selector: #selector(emergencyColorExpired),
                      userInfo: nil, repeats: false)
        RunLoop.main.add(t, forMode: .common)
        emergencyColorTimer = t
        if firstActivation {
            // Remember grayscale, then drop it for real colours. Recorded once so a
            // re-arm can't overwrite it; restored verbatim on cancel.
            grayscaleBeforeEmergency = grayscaleEngine.isGrayscaleEnabled()
            if grayscaleBeforeEmergency { grayscaleEngine.setGrayscale(false) }
        }
        applyEffectiveState()
        NotificationCenter.default.post(name: Self.emergencyColorChanged, object: nil)
    }

    @objc private func emergencyColorExpired() { cancelEmergencyColor() }

    func cancelEmergencyColor() {
        guard isEmergencyColorActive else { return }
        emergencyColorTimer?.invalidate()
        emergencyColorTimer = nil
        emergencyColorEndDate = nil
        // Restore grayscale to exactly what it was before — unconditionally, so a
        // laggy system-state read can't lose it. If WE turned it off, turn it back on.
        if grayscaleBeforeEmergency {
            grayscaleEngine.setGrayscale(true)
        }
        // Keep the schedule's edge-trigger consistent with the grayscale we just
        // restored, so its next tick doesn't fight it.
        scheduledGrayscale = grayscaleBeforeEmergency ? true : nil
        applyEffectiveState()   // colour/dim back for the underlying mode
        NotificationCenter.default.post(name: Self.emergencyColorChanged, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave the screen exactly as macOS expects: gamma restored, colour back on.
        emergencyColorTimer?.invalidate()
        gammaEngine.shutdown()
        grayscaleEngine.shutdown()
    }
}
