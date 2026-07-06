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
    }

    private init() {
        // Sensible first-launch defaults: off, ~3500 K warmth (f.lux's sunset zone —
        // warm enough to feel on first try, not the deep-red end), no dimming.
        defaults.register(defaults: [
            Key.masterEnabled: false,
            Key.warmth: 0.65,
            Key.dim: 0.0,
            Key.grayscaleOn: false
        ])
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

    private func clamp(_ v: Double) -> Double { min(1.0, max(0.0, v)) }

    private func notify() {
        NotificationCenter.default.post(name: PreferencesStore.didChange, object: nil)
    }
}
