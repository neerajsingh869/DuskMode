import CoreLocation
import Foundation

/// Supplies the coordinates the solar calculator needs, without ever blocking the
/// schedule on a permission prompt:
///
/// 1. Best: a real CoreLocation fix (city-level accuracy is plenty for sunset times),
///    requested once when the schedule is enabled and cached in preferences.
/// 2. Fallback: the cached fix from a previous run.
/// 3. Last resort: approximate coordinates derived from the system timezone
///    (longitude from the UTC offset, a temperate default latitude). Sunset is then
///    off by tens of minutes at worst — the schedule still works on day one.
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    struct Coordinates {
        let latitude: Double
        let longitude: Double
        let isApproximate: Bool
    }

    /// Called after a fresh fix lands, so the schedule can recompute.
    var onUpdate: (() -> Void)?

    private let manager = CLLocationManager()
    private let prefs = PreferencesStore.shared
    private var hasRequested = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    /// Best available coordinates right now. Never blocks, never prompts.
    var coordinates: Coordinates {
        if let lat = prefs.cachedLatitude, let lon = prefs.cachedLongitude {
            return Coordinates(latitude: lat, longitude: lon, isApproximate: false)
        }
        let offsetHours = Double(TimeZone.current.secondsFromGMT()) / 3600
        return Coordinates(latitude: 25, longitude: offsetHours * 15, isApproximate: true)
    }

    /// Ask for a one-shot fix (prompting for permission if needed). Safe to call
    /// repeatedly; only the first call per launch does anything.
    func requestFix() {
        guard !hasRequested else { return }
        hasRequested = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // fix requested on grant, below
        case .authorizedAlways:
            manager.requestLocation()
        default:
            break                                     // denied/restricted → fallbacks
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways, hasRequested {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        prefs.setCachedLocation(latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude)
        onUpdate?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep whatever cache/approximation we have — the schedule must never stall.
    }
}
