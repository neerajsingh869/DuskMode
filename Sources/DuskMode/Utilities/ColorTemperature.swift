import Foundation

/// Correlated colour temperature maths shared by the gamma and overlay engines.
///
/// Warmth (the 0…1 slider) maps linearly to Kelvin: 6500 K (neutral daylight —
/// display untouched) down to 1900 K (candlelight, the deep end of f.lux's range).
/// Per-channel RGB multipliers come from the standard blackbody approximation
/// (Tanner Helland's curve fit), normalised so 6500 K is exactly (1, 1, 1).
/// This is what makes the tint read as warm *orange* light rather than a red film:
/// at 3400 K the green channel keeps ~77% — hardcoded amber/red hues cut green far
/// too hard, which was why the old tint looked reddish next to f.lux.
enum ColorTemperature {

    static let neutralKelvin: Double = 6500
    static let minKelvin: Double = 1900

    static func kelvin(forWarmth warmth: Double) -> Double {
        let w = min(1, max(0, warmth))
        return neutralKelvin - w * (neutralKelvin - minKelvin)
    }

    /// Per-channel multiplier (each 0…1; red is always 1) for a colour temperature.
    static func multiplier(forKelvin kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let raw = blackbody(kelvin)
        let ref = blackbody(neutralKelvin)
        return (min(1, raw.r / ref.r),
                min(1, raw.g / ref.g),
                min(1, raw.b / ref.b))
    }

    static func multiplier(forWarmth warmth: Double) -> (r: Double, g: Double, b: Double) {
        multiplier(forKelvin: kelvin(forWarmth: warmth))
    }

    /// Blackbody RGB (0…1), Tanner Helland's approximation. Valid ~1000–40000 K.
    private static func blackbody(_ kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(400, max(10, kelvin / 100))
        let r: Double, g: Double, b: Double
        if t <= 66 {
            r = 255
            g = 99.4708025861 * log(t) - 161.1195681661
        } else {
            r = 329.698727446 * pow(t - 60, -0.1332047592)
            g = 288.1221695283 * pow(t - 60, -0.0755148492)
        }
        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.5177312231 * log(t - 10) - 305.0447927307
        }
        func norm(_ v: Double) -> Double { min(255, max(0, v)) / 255 }
        return (norm(r), norm(g), norm(b))
    }
}
