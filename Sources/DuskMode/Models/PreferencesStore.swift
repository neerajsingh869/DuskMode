import Foundation

/// All user-adjustable settings, persisted in UserDefaults.
/// Phase 1 scope: master toggle, warmth, dim, grayscale state.
/// Later phases add the timeline, whitelist, keyboard shortcut, etc.
final class PreferencesStore {

    static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard

    /// Posted whenever any value changes so engines can react.
    static let didChange = Notification.Name("DuskMode.PreferencesDidChange")

    private enum Key {
        static let masterEnabled = "masterEnabled"
        static let warmth = "warmth"
        static let dim = "dim"
        static let grayscaleOn = "grayscaleOn"
        static let scheduleEnabled = "scheduleEnabled"
        static let bedtimeMinutes = "bedtimeMinutes"
        static let cachedLatitude = "cachedLatitude"
        static let cachedLongitude = "cachedLongitude"
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
        // Master and schedule start off until the user opts in.
        defaults.register(defaults: [
            Key.masterEnabled: false,
            Key.warmth: Default.warmth,
            Key.dim: Default.dim,
            Key.grayscaleOn: false,
            Key.scheduleEnabled: false,
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

    /// Master on/off for the whole filtering stack.
    var masterEnabled: Bool {
        get { defaults.bool(forKey: Key.masterEnabled) }
        set { defaults.set(newValue, forKey: Key.masterEnabled); notify() }
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

    /// Whether the automatic circadian schedule is driving the filters.
    /// While true, manual warmth/dim/master values are ignored (schedule wins);
    /// any manual adjustment in the UI flips this back to false.
    var scheduleEnabled: Bool {
        get { defaults.bool(forKey: Key.scheduleEnabled) }
        set { defaults.set(newValue, forKey: Key.scheduleEnabled); notify() }
    }

    /// Target bedtime as minutes after midnight (0…1439). Values before noon are
    /// treated as "after midnight" (e.g. 30 = 00:30 the next morning).
    var bedtimeMinutes: Int {
        get { min(1439, max(0, defaults.integer(forKey: Key.bedtimeMinutes))) }
        set { defaults.set(min(1439, max(0, newValue)), forKey: Key.bedtimeMinutes); notify() }
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
