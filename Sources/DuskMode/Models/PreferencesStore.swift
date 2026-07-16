import Foundation

/// All user-adjustable settings, persisted in UserDefaults.
/// Phase 1 scope: master toggle, warmth, dim, grayscale state.
/// Later phases add the timeline, whitelist, keyboard shortcut, etc.
final class PreferencesStore {

    static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard

    /// Posted whenever any value changes so engines can react.
    static let didChange = Notification.Name("DuskMode.PreferencesDidChange")

    /// The single top-level state, replacing the old master + schedule switches.
    /// off = screen untouched · manual = warmth/dim sliders drive · auto = schedule drives.
    enum Mode: String {
        case off, manual, auto
    }

    private enum Key {
        static let mode = "mode"
        static let masterEnabled = "masterEnabled"     // legacy — read only for migration
        static let warmth = "warmth"
        static let dim = "dim"
        static let grayscaleOn = "grayscaleOn"
        static let scheduleEnabled = "scheduleEnabled" // legacy — read only for migration
        static let bedtimeMinutes = "bedtimeMinutes"
        static let cachedLatitude = "cachedLatitude"
        static let cachedLongitude = "cachedLongitude"
        static let whitelistedApps = "whitelistedApps"
        static let hasConfiguredLaunchAtLogin = "hasConfiguredLaunchAtLogin"
    }

    /// First-launch values — also what the popover's "Reset to Defaults" restores.
    /// ~3500 K warmth (f.lux's sunset zone — warm enough to feel on first try, not
    /// the deep-red end), no dimming, grayscale off, bedtime 23:00.
    enum Default {
        static let warmth = 0.65
        static let dim = 0.0
        static let bedtimeMinutes = 23 * 60
    }

    private init() {
        defaults.register(defaults: [
            Key.warmth: Default.warmth,
            Key.dim: Default.dim,
            Key.grayscaleOn: false,
            Key.bedtimeMinutes: Default.bedtimeMinutes
        ])
    }

    /// Restore the tunable values (warmth, dim, grayscale, bedtime) to first-launch
    /// defaults. Mode switches (master, schedule) are deliberately untouched — reset
    /// puts the knobs back, it doesn't turn the app on or off.
    func resetToDefaults() {
        defaults.set(Default.warmth, forKey: Key.warmth)
        defaults.set(Default.dim, forKey: Key.dim)
        defaults.set(false, forKey: Key.grayscaleOn)
        defaults.set(Default.bedtimeMinutes, forKey: Key.bedtimeMinutes)
        notify()
    }

    /// The single top-level state. Migrates once from the old master/schedule switches
    /// so an existing install resumes in the equivalent mode.
    var mode: Mode {
        get {
            if let raw = defaults.string(forKey: Key.mode), let m = Mode(rawValue: raw) {
                return m
            }
            if defaults.bool(forKey: Key.scheduleEnabled) { return .auto }
            if defaults.bool(forKey: Key.masterEnabled) { return .manual }
            return .off
        }
        set { defaults.set(newValue.rawValue, forKey: Key.mode); notify() }
    }

    /// 0.0 = neutral/amber, 1.0 = deep red. Drives the overlay tint.
    var warmth: Double {
        get { clamp(defaults.double(forKey: Key.warmth)) }
        set { defaults.set(clamp(newValue), forKey: Key.warmth); notify() }
    }

    /// 0.0 = no dimming, 1.0 = maximum sub-hardware dimming. Drives the overlay alpha.
    var dim: Double {
        get { clamp(defaults.double(forKey: Key.dim)) }
        set { defaults.set(clamp(newValue), forKey: Key.dim); notify() }
    }

    /// Whether the user has grayscale toggled on (best-effort mirror of system state).
    var grayscaleOn: Bool {
        get { defaults.bool(forKey: Key.grayscaleOn) }
        set { defaults.set(newValue, forKey: Key.grayscaleOn); notify() }
    }

    /// Target bedtime as minutes after midnight (0…1439). Values before noon are
    /// treated as "after midnight" (e.g. 30 = 00:30 the next morning).
    var bedtimeMinutes: Int {
        get { min(1439, max(0, defaults.integer(forKey: Key.bedtimeMinutes))) }
        set { defaults.set(min(1439, max(0, newValue)), forKey: Key.bedtimeMinutes); notify() }
    }

    /// Apps that pause DuskMode while they're frontmost (bundle ID → display name,
    /// captured at add time so the list can be shown even when the app isn't running).
    /// Pausing drops warmth + grayscale for true colour; dimming stays — brightness is
    /// the melatonin-critical layer and doesn't shift hue. Default: empty — every
    /// escape hatch is one the user deliberately chose (Phase 3, intentionality).
    var whitelistedApps: [String: String] {
        (defaults.dictionary(forKey: Key.whitelistedApps) as? [String: String]) ?? [:]
    }

    func isWhitelisted(_ bundleID: String) -> Bool {
        whitelistedApps[bundleID] != nil
    }

    /// Add or remove an app from the pause list. `name` is only stored on add.
    func setWhitelisted(_ whitelisted: Bool, bundleID: String, name: String) {
        var apps = whitelistedApps
        if whitelisted { apps[bundleID] = name } else { apps.removeValue(forKey: bundleID) }
        defaults.set(apps, forKey: Key.whitelistedApps)
        notify()
    }

    /// One-time latch: has the app already registered itself for launch-at-login on
    /// first run? After this, the popover switch has full manual control — we never
    /// force it back on. (The actual enabled/disabled state lives in SMAppService, not
    /// here — this flag only gates the one-time auto-registration.)
    var hasConfiguredLaunchAtLogin: Bool {
        get { defaults.bool(forKey: Key.hasConfiguredLaunchAtLogin) }
        set { defaults.set(newValue, forKey: Key.hasConfiguredLaunchAtLogin) }
    }

    /// Last CoreLocation fix, so sunset stays accurate across launches even if
    /// location access later fails. Nil until the first successful fix.
    var cachedLatitude: Double? { defaults.object(forKey: Key.cachedLatitude) as? Double }
    var cachedLongitude: Double? { defaults.object(forKey: Key.cachedLongitude) as? Double }

    func setCachedLocation(latitude: Double, longitude: Double) {
        defaults.set(latitude, forKey: Key.cachedLatitude)
        defaults.set(longitude, forKey: Key.cachedLongitude)
        notify()
    }

    private func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }

    private func notify() {
        NotificationCenter.default.post(name: PreferencesStore.didChange, object: nil)
    }
}
