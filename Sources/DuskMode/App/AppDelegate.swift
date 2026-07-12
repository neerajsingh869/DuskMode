import AppKit
import Carbon.HIToolbox
import DuskModeCore

/// Small surface the popover uses to drive screen state — Emergency Color and manual
/// grayscale ownership — without knowing about the whole AppDelegate.
protocol ScreenStateControlling: AnyObject {
    var isEmergencyColorActive: Bool { get }
    var emergencyColorEndDate: Date? { get }
    /// True only when there's actually a filter to suspend (colour/dim on via manual
    /// or an active schedule, or grayscale on). The button/hotkey are no-ops otherwise.
    var isEmergencyColorAvailable: Bool { get }
    /// True while something (Emergency Color, or a whitelisted app being frontmost) is
    /// momentarily holding grayscale off. The UI shows the grayscale switch as ON in
    /// this case — the setting is intact, just suspended.
    var grayscaleSuspended: Bool { get }
    /// The app the popover's "Pause for …" switch acts on: the frontmost regular app
    /// (DuskMode itself excluded). Nil until the first activation is seen.
    var frontmostPausableApp: (bundleID: String, name: String)? { get }
    func toggleEmergencyColor()
    /// The user tapped the grayscale switch (or Reset). Marks grayscale as a manual,
    /// independent peer (not schedule-owned) so it survives a later mode change, and
    /// edge-guards the system toggle so an unchanged state fires no stray bezel.
    func setManualGrayscale(_ enabled: Bool)
}

final class AppDelegate: NSObject, NSApplicationDelegate, ScreenStateControlling {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    let overlayEngine = OverlayEngine()
    let gammaEngine = GammaEngine()
    let grayscaleEngine: GrayscaleControlling
    let circadianEngine = CircadianEngine()

    /// Grayscale is injectable so a recording double can exercise the ownership state
    /// machine without touching real system grayscale; production uses GrayscaleEngine.
    init(grayscaleEngine: GrayscaleControlling = GrayscaleEngine()) {
        self.grayscaleEngine = grayscaleEngine
        super.init()
    }

    /// Last grayscale state the *schedule* asked for. Grayscale is only touched when
    /// this changes (edge-triggered): the macOS Colour Filters bezel would otherwise
    /// fire every 30s tick, and a manual grayscale toggle mid-phase would be fought.
    private var scheduledGrayscale: Bool?

    /// Whether the grayscale currently ON originated from the SCHEDULE (or was inherited
    /// when a slider handoff moved a scheduled state into manual mode) vs. the user
    /// tapping the grayscale switch by hand. Auto-owned grayscale is released when the
    /// screen returns FULLY to normal; a hand-toggled grayscale is an independent peer
    /// and is left alone (REGRESSIONS #14/#15). Survives a handoff (stays auto-owned).
    private var grayscaleFromSchedule = false

    // MARK: Grayscale suppression (Emergency Color + app pause share ONE mechanism)
    /// Both Emergency Color and the app whitelist need "hold grayscale off for a while,
    /// then put back exactly what was there". Two independent save/restore pairs would
    /// collide (e.g. switching away from a paused app mid-emergency must NOT re-enable
    /// grayscale while the emergency still holds it off), so they share one suppressor
    /// set with one saved intent: the FIRST suppressor records+drops the grayscale, the
    /// LAST one to leave restores it — unconditionally, never gated on a read-back of
    /// the laggy UA getter (REGRESSIONS #12).
    private enum GrayscaleSuppressor { case emergency, appPause }
    private var grayscaleSuppressors: Set<GrayscaleSuppressor> = []
    private var grayscaleIntentBeforeSuppression = false

    // MARK: App whitelist (Phase 3)
    /// The last frontmost regular app (DuskMode itself excluded). When it's in the
    /// user's pause list, warmth + grayscale are suspended for true colour while
    /// DIMMING STAYS — brightness is the melatonin-critical layer and doesn't shift
    /// hue, so the pause grants colour accuracy without opening a full escape hatch.
    private var frontmostBundleID: String?
    private var frontmostAppName: String?
    private(set) var isPausedForFrontmostApp = false

    // MARK: Emergency Color (Phase 3)
    /// A momentary "I need real colours NOW" override that suspends every filter for
    /// a fixed window, then auto-reverts to whatever mode was running (manual or
    /// schedule). Sits ABOVE both apply paths via `applyEffectiveState`.
    static let emergencyColorChanged = Notification.Name("DuskMode.EmergencyColorChanged")
    static let emergencyColorDuration: TimeInterval = 60
    private var emergencyColorTimer: Timer?
    private(set) var emergencyColorEndDate: Date?
    private var emergencyHotKey: GlobalHotKey?

    var isEmergencyColorActive: Bool { emergencyColorEndDate != nil }

    /// While a suppressor is holding grayscale off, the user's grayscale intent is
    /// still ON — the switch should show that, not the suspended system state.
    var grayscaleSuspended: Bool { !grayscaleSuppressors.isEmpty && grayscaleIntentBeforeSuppression }

    var frontmostPausableApp: (bundleID: String, name: String)? {
        guard let id = frontmostBundleID else { return nil }
        return (id, frontmostAppName ?? id)
    }

    /// Something is currently filtering the screen, so there's a point to Emergency
    /// Color: colour/dim on (manual, or an active schedule) OR grayscale on.
    var isEmergencyColorAvailable: Bool {
        let colourActive: Bool
        switch PreferencesStore.shared.mode {
        case .auto:   colourActive = circadianEngine.currentTarget.active
        case .manual: colourActive = true
        case .off:    colourActive = false
        }
        return colourActive || grayscaleEngine.isGrayscaleEnabled()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Every tick re-evaluates through the single choke point so an active
        // Emergency Color override always wins over the schedule.
        circadianEngine.onTarget = { [weak self] _ in
            self?.applyEffectiveState()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: PreferencesStore.didChange, object: nil)

        setupStatusItem()
        setupPopover()

        // Global shortcut → Emergency Color. Public Carbon hotkey (⌥⌘C), no
        // Accessibility permission needed. Nil if the combo is already taken.
        emergencyHotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_C),
                                       modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleEmergencyColor()
        }

        // App whitelist: watch the frontmost app so filters pause for whitelisted
        // creative apps. Observation only — NEVER reorder windows from this observer
        // (REGRESSIONS #1); the pause flows through the same apply choke point.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontmostAppDidChange),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            noteFrontmostApp(bundleID: front.bundleIdentifier, name: front.localizedName)
        }

        // Reflect any persisted state on launch.
        preferencesChanged()
    }

    // MARK: - App whitelist (pause while a whitelisted app is frontmost)

    @objc private func frontmostAppDidChange(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        noteFrontmostApp(bundleID: app.bundleIdentifier, name: app.localizedName)
    }

    /// Internal (not private) so verification can drive the real pause path without
    /// fabricating NSRunningApplication instances.
    func noteFrontmostApp(bundleID: String?, name: String?) {
        guard let bundleID else { return }   // agent processes without an ID — keep last known
        frontmostBundleID = bundleID
        frontmostAppName = name
        if updateAppPauseState() { applyEffectiveState() }
    }

    /// Recompute whether the frontmost app pauses DuskMode; handles the grayscale
    /// suppression transitions. Returns true when the pause state changed.
    @discardableResult
    private func updateAppPauseState() -> Bool {
        let shouldPause = frontmostBundleID.map { PreferencesStore.shared.isWhitelisted($0) } ?? false
        guard shouldPause != isPausedForFrontmostApp else { return false }
        // Flip the flag FIRST: suppress/unsuppress touch system grayscale, which posts
        // a prefs change, and that reentrant applyEffectiveState must already resolve
        // through the new pause state.
        isPausedForFrontmostApp = shouldPause
        if shouldPause { suppressGrayscale(.appPause) } else { unsuppressGrayscale(.appPause) }
        return true
    }

    // MARK: - Grayscale suppression (shared by Emergency Color and app pause)

    private func suppressGrayscale(_ reason: GrayscaleSuppressor) {
        guard !grayscaleSuppressors.contains(reason) else { return }
        let isFirst = grayscaleSuppressors.isEmpty
        grayscaleSuppressors.insert(reason)
        guard isFirst else { return }
        // Record once, so a re-arm or a second suppressor can't overwrite it.
        grayscaleIntentBeforeSuppression = grayscaleEngine.isGrayscaleEnabled()
        if grayscaleIntentBeforeSuppression { grayscaleEngine.setGrayscale(false) }
    }

    private func unsuppressGrayscale(_ reason: GrayscaleSuppressor) {
        guard grayscaleSuppressors.remove(reason) != nil, grayscaleSuppressors.isEmpty else { return }
        // Restore is UNCONDITIONAL on the saved intent — never gate on a read-back of
        // the current system state; the UA getter lags right after a set (#12).
        if grayscaleIntentBeforeSuppression {
            grayscaleEngine.setGrayscale(true)
        }
        // Keep the schedule's edge-trigger consistent with what we just restored, so
        // its next tick doesn't fight it.
        scheduledGrayscale = grayscaleIntentBeforeSuppression ? true : nil
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
        // The whitelist may have been edited (or grayscale suppression re-entered
        // here) — recompute whether the frontmost app pauses DuskMode.
        updateAppPauseState()
        let mode = PreferencesStore.shared.mode
        if mode == .auto {
            // The circadian schedule owns the screen: (re)start it. Its target flows
            // through onTarget → applyEffectiveState. Manual values are ignored.
            circadianEngine.setEnabled(true)
        } else if circadianEngine.isEnabled {
            // Just LEFT Auto. The schedule no longer drives grayscale — release the
            // grayscale it owned so leaving Auto reverts what Auto did (REGRESSIONS #16).
            // With the sliders removed from Auto (#20) the explicit mode click is the
            // only way out, so the release is unconditional. Skipped during an
            // emergency (grayscale is momentarily off then; cancel restores it).
            circadianEngine.setEnabled(false)
            scheduledGrayscale = nil
            if grayscaleFromSchedule, !isEmergencyColorActive {
                if grayscaleEngine.isGrayscaleEnabled() {
                    grayscaleEngine.setGrayscale(false)
                } else if grayscaleSuppressors.contains(.appPause) {
                    // The schedule's grayscale is currently suspended by a paused app.
                    // Releasing it means "don't bring it back when the pause ends".
                    grayscaleIntentBeforeSuppression = false
                }
            }
            grayscaleFromSchedule = false
        }
        // NOTE: grayscale is a fully independent behavioral tool (REGRESSIONS #17) —
        // available in ANY mode, including Off. A grayscale the user toggled by hand is
        // NEVER swept by a mode change (only its own toggle or app quit turns it off);
        // only the schedule's own grayscale is released, above, when leaving Auto.
        applyEffectiveState()
    }

    // MARK: - Apply choke point

    /// The single place the screen state is decided. Emergency Color overrides
    /// everything; otherwise the current mode (auto / manual / off) drives.
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
        switch prefs.mode {
        case .auto:
            let target = circadianEngine.currentTarget
            if isPausedForFrontmostApp {
                // Paused for a whitelisted app: warmth drops to neutral for true
                // colour (grayscale is held off by the suppressor, handled on the
                // pause transitions), but the DIM STAYS — brightness is the
                // melatonin-critical layer and doesn't shift hue. The schedule's
                // grayscale edge-trigger is deliberately frozen while paused; the
                // first apply after unpausing reconciles any boundary crossed.
                applyFilters(enabled: target.active, warmth: 0, dim: target.dim)
            } else {
                applyScheduleTarget(target)
            }
        case .manual:
            applyFilters(enabled: true,
                         warmth: isPausedForFrontmostApp ? 0 : prefs.warmth,
                         dim: prefs.dim)
        case .off:
            applyFilters(enabled: false, warmth: 0, dim: 0)
        }
    }

    /// Drive colour+dim through the engines. Gamma carries BOTH whenever it works: it
    /// isn't a window, so it can never flash during app switches (REGRESSIONS.md #9).
    /// Only when gamma is unavailable (newest-Apple-Silicon regression) does the overlay
    /// window exist at all, carrying both layers with the same blackbody hue.
    private func applyFilters(enabled: Bool, warmth: Double, dim: Double) {
        let gammaHandlesFilters = gammaEngine.apply(enabled: enabled, warmth: warmth, dim: dim)
        overlayEngine.apply(enabled: enabled && !gammaHandlesFilters, warmth: warmth, dim: dim)
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
            // The schedule now owns this grayscale (on → auto-owned, so it's released
            // when the app returns to normal; off → nothing to own).
            grayscaleFromSchedule = target.grayscale
        }
    }

    // MARK: - Emergency Color

    func toggleEmergencyColor() {
        if isEmergencyColorActive { cancelEmergencyColor() }
        else if isEmergencyColorAvailable { activateEmergencyColor() }
        // Nothing filtered → nothing to suspend; button/hotkey do nothing.
    }

    /// The user tapped the grayscale switch (or Reset). This is an explicit, manual
    /// choice, so the grayscale becomes an INDEPENDENT peer — `grayscaleFromSchedule`
    /// is cleared, so a later master/schedule off won't sweep it (REGRESSIONS #15). The
    /// system toggle is edge-guarded so re-asserting an unchanged state fires no bezel.
    /// Deliberately does NOT touch `scheduledGrayscale` — if the schedule is running, it
    /// re-asserts grayscale only at the next phase boundary, not immediately.
    func setManualGrayscale(_ enabled: Bool) {
        grayscaleFromSchedule = false
        if !grayscaleSuppressors.isEmpty {
            // The screen is momentarily unfiltered (emergency, or a paused app is
            // frontmost). Don't fight the suppression — record the user's intent so
            // the restore honours it when the suppression ends.
            grayscaleIntentBeforeSuppression = enabled
            PreferencesStore.shared.grayscaleOn = enabled
            return
        }
        // Keep the intent mirror true even when the system toggle is edge-guarded
        // away, so the switch never drifts from a stale pref.
        PreferencesStore.shared.grayscaleOn = enabled
        if grayscaleEngine.isGrayscaleEnabled() != enabled {
            grayscaleEngine.setGrayscale(enabled)
        }
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
            // Remember grayscale, then drop it for real colours — via the shared
            // suppressor, so an app pause running at the same time can't collide.
            suppressGrayscale(.emergency)
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
        // Restore grayscale to exactly what it was before (unconditional on the saved
        // intent, #12) — unless a paused app still holds the suppression, in which
        // case the restore waits for the unpause.
        unsuppressGrayscale(.emergency)
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
