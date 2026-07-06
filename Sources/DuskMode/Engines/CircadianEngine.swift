import AppKit
import DuskModeCore

/// Phase 2: the circadian brain. Ticks a 30-second timer while the automatic
/// schedule is on, evaluates the CircadianTimeline for "now", and hands the target
/// to AppDelegate to apply through the same gamma/overlay/grayscale engines the
/// manual sliders use. Recomputes immediately after wake from sleep and after
/// system clock changes (timezone/DST/manual), so the schedule can't drift.
final class CircadianEngine {

    /// Fired on every tick with the current target (idempotent to re-apply —
    /// pushing unchanged values every 30s doubles as self-healing reassertion).
    var onTarget: ((CircadianTimeline.Target) -> Void)?

    private(set) var currentTarget = CircadianTimeline.Target(
        warmth: 0, dim: 0, grayscale: false, active: false,
        phaseName: "Off", nextEventName: nil, nextEventTime: nil)

    var isEnabled: Bool { timer != nil }
    var usesApproximateLocation: Bool { locationProvider.coordinates.isApproximate }

    private let prefs = PreferencesStore.shared
    private let locationProvider = LocationProvider()
    private var timer: Timer?

    init() {
        locationProvider.onUpdate = { [weak self] in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(wokeFromSleep),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clockChanged),
            name: .NSSystemClockDidChange, object: nil)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            if enabled { refresh() }   // already running — bedtime may have changed
            return
        }
        if enabled {
            locationProvider.requestFix()
            let t = Timer(timeInterval: 30, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
            t.tolerance = 5            // let macOS coalesce wakeups — CPU stays ~0
            RunLoop.main.add(t, forMode: .common)
            timer = t
            refresh()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Recompute and push the target for this instant.
    func refresh() {
        guard isEnabled else { return }
        let now = Date()
        currentTarget = CircadianTimeline.around(
            now,
            latitude: locationProvider.coordinates.latitude,
            longitude: locationProvider.coordinates.longitude,
            bedtimeMinutes: prefs.bedtimeMinutes
        ).target(at: now)
        onTarget?(currentTarget)
    }

    @objc private func tick() { refresh() }

    @objc private func wokeFromSleep() {
        // Give displays a moment to settle, then snap to where the timeline is now
        // (the timer may have been suspended for hours).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func clockChanged() { refresh() }
}
