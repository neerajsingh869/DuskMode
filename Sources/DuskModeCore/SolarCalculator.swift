import Foundation

/// Sunrise/sunset from the NOAA solar-position equations (public domain),
/// implemented from the NOAA spreadsheet ourselves per project rule #6
/// (no third-party dependencies). Accurate to ~1 minute for |latitude| < 72°.
public enum SolarCalculator {

    public struct SunTimes {
        public let sunrise: Date
        public let sunset: Date
        public let solarNoon: Date
    }

    /// Sun times for the calendar day containing `date` in `timeZone`.
    /// Longitude is east-positive (Delhi ≈ +77.2, New York ≈ −74.0).
    /// Returns nil during polar day/night, when the sun never crosses the horizon.
    public static func sunTimes(on date: Date,
                         latitude: Double,
                         longitude: Double,
                         timeZone: TimeZone = .current) -> SunTimes? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = calendar.startOfDay(for: date)
        let localNoon = midnight.addingTimeInterval(12 * 3600)

        // Julian century relative to J2000, evaluated at local noon. The sun's
        // parameters drift less than the algorithm's accuracy within one day,
        // so a single evaluation covers both sunrise and sunset.
        let julianDay = localNoon.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (julianDay - 2451545) / 36525

        func rad(_ d: Double) -> Double { d * .pi / 180 }
        func deg(_ r: Double) -> Double { r * 180 / .pi }

        let meanLong = (280.46646 + t * (36000.76983 + t * 0.0003032))
            .truncatingRemainder(dividingBy: 360)
        let meanAnom = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let eqOfCenter = sin(rad(meanAnom)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * meanAnom)) * (0.019993 - 0.000101 * t)
            + sin(rad(3 * meanAnom)) * 0.000289
        let trueLong = meanLong + eqOfCenter
        let apparentLong = trueLong - 0.00569 - 0.00478 * sin(rad(125.04 - 1934.136 * t))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(rad(125.04 - 1934.136 * t))
        let declination = asin(sin(rad(obliquity)) * sin(rad(apparentLong)))

        let y = pow(tan(rad(obliquity / 2)), 2)
        let eqOfTimeMinutes = 4 * deg(
            y * sin(2 * rad(meanLong))
            - 2 * eccentricity * sin(rad(meanAnom))
            + 4 * eccentricity * y * sin(rad(meanAnom)) * cos(2 * rad(meanLong))
            - 0.5 * y * y * sin(4 * rad(meanLong))
            - 1.25 * eccentricity * eccentricity * sin(2 * rad(meanAnom)))

        // Zenith 90.833° = "official" sunrise/sunset: the solar disc's radius plus
        // standard atmospheric refraction.
        let latRad = rad(latitude)
        let cosHourAngle = cos(rad(90.833)) / (cos(latRad) * cos(declination))
            - tan(latRad) * tan(declination)
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        let hourAngleMinutes = 4 * deg(acos(cosHourAngle))

        let tzOffsetMinutes = Double(timeZone.secondsFromGMT(for: localNoon)) / 60
        let solarNoonMinutes = 720 - 4 * longitude - eqOfTimeMinutes + tzOffsetMinutes

        func time(_ minutesAfterMidnight: Double) -> Date {
            midnight.addingTimeInterval(minutesAfterMidnight * 60)
        }
        return SunTimes(sunrise: time(solarNoonMinutes - hourAngleMinutes),
                        sunset: time(solarNoonMinutes + hourAngleMinutes),
                        solarNoon: time(solarNoonMinutes))
    }
}
