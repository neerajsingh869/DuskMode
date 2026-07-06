import Foundation

/// The pure maths of one evening's wind-down: builds the keyframe ladder from
/// sunset/bedtime/sunrise and answers "what should the screen look like right now".
/// No AppKit, no timers, no I/O — CircadianEngine drives it, unit tests exercise it.
///
/// Phase ladder and numbers come straight from research/notes.md:
/// - Sunset    (at sunset)      5000 K, dim 10%           — gentle early wind-down
/// - Warm      (bedtime − 2.5h) 3400 K, dim 20%           — DLMO window opens 2–3h before bed
/// - Grayscale (bedtime − 2h)   2700 K, dim 30%, gray ON  — doomscroll window
/// - Red       (bedtime − 1h)   1900 K, dim 50%           — 620–670nm safe tail
/// - Bedtime   (at bedtime)     1900 K, dim 80%           — toward the ≤1 lux goal
/// Everything reverts at sunrise. Each phase ramps in over 25–30 min
/// (research: 20–30 min transitions feel gradual, not jarring).
public struct CircadianTimeline {

    public struct Target: Equatable {
        public var warmth: Double
        public var dim: Double
        public var grayscale: Bool
        public var active: Bool            // false = daytime, screen untouched
        public var phaseName: String
        public var nextEventName: String?
        public var nextEventTime: Date?

        public init(warmth: Double, dim: Double, grayscale: Bool, active: Bool,
                    phaseName: String, nextEventName: String?, nextEventTime: Date?) {
            self.warmth = warmth
            self.dim = dim
            self.grayscale = grayscale
            self.active = active
            self.phaseName = phaseName
            self.nextEventName = nextEventName
            self.nextEventTime = nextEventTime
        }
    }

    public struct Keyframe {
        public let start: Date             // ramp toward this keyframe's values begins here
        public let ramp: TimeInterval
        public let warmth: Double
        public let dim: Double
        public let grayscale: Bool         // flips at start (binary — can't be interpolated)
        public let name: String
    }

    public let keyframes: [Keyframe]
    public let end: Date            // sunrise — everything off

    public init(sunset: Date, bedtime: Date, sunrise: Date) {
        struct Preset {
            let nominal: Date, ramp: TimeInterval
            let kelvin: Double, dim: Double, gray: Bool, name: String
        }
        // Sunset never starts later than 3h before bed, so short evenings
        // (early bedtimes, late summer sunsets) still get a full wind-down.
        let sunsetStart = min(sunset, bedtime.addingTimeInterval(-3 * 3600))
        let presets = [
            Preset(nominal: sunsetStart, ramp: 30 * 60,
                   kelvin: 5000, dim: 0.10, gray: false, name: "Sunset"),
            Preset(nominal: bedtime.addingTimeInterval(-2.5 * 3600), ramp: 25 * 60,
                   kelvin: 3400, dim: 0.20, gray: false, name: "Warm"),
            Preset(nominal: bedtime.addingTimeInterval(-2 * 3600), ramp: 25 * 60,
                   kelvin: 2700, dim: 0.30, gray: true, name: "Grayscale"),
            Preset(nominal: bedtime.addingTimeInterval(-1 * 3600), ramp: 25 * 60,
                   kelvin: 1900, dim: 0.50, gray: true, name: "Red"),
            Preset(nominal: bedtime, ramp: 25 * 60,
                   kelvin: 1900, dim: 0.80, gray: true, name: "Bedtime")
        ]
        // Keep keyframes strictly ordered: each starts no earlier than 5 min after
        // the previous ramp completes, so a squeezed evening degrades gracefully
        // instead of phases landing on top of each other.
        var frames: [Keyframe] = []
        for preset in presets {
            var start = preset.nominal
            if let previous = frames.last {
                start = max(start, previous.start.addingTimeInterval(previous.ramp + 5 * 60))
            }
            frames.append(Keyframe(start: start, ramp: preset.ramp,
                                   warmth: ColorTemperature.warmth(forKelvin: preset.kelvin),
                                   dim: preset.dim, grayscale: preset.gray,
                                   name: preset.name))
        }
        keyframes = frames
        // Sunrise must land after the ladder even in degenerate inputs.
        end = max(sunrise, frames.last!.start.addingTimeInterval(30 * 60))
    }

    public func target(at now: Date) -> Target {
        let day = Target(warmth: 0, dim: 0, grayscale: false, active: false,
                         phaseName: "Day",
                         nextEventName: keyframes[0].name,
                         nextEventTime: keyframes[0].start)
        guard now >= keyframes[0].start, now < end else { return day }

        // Walk the ladder: settled between keyframes, interpolating inside a ramp.
        var previousWarmth = 0.0
        var previousDim = 0.0
        for (index, frame) in keyframes.enumerated() {
            let next: (String, Date) = index + 1 < keyframes.count
                ? (keyframes[index + 1].name, keyframes[index + 1].start)
                : ("Sunrise", end)
            if now < frame.start {
                break   // settled in the previous frame — handled below via index-1
            }
            let rampEnd = frame.start.addingTimeInterval(frame.ramp)
            if now < rampEnd {
                let fraction = now.timeIntervalSince(frame.start) / frame.ramp
                return Target(warmth: previousWarmth + (frame.warmth - previousWarmth) * fraction,
                              dim: previousDim + (frame.dim - previousDim) * fraction,
                              grayscale: frame.grayscale, active: true,
                              phaseName: frame.name,
                              nextEventName: next.0, nextEventTime: next.1)
            }
            if index + 1 == keyframes.count || now < keyframes[index + 1].start {
                return Target(warmth: frame.warmth, dim: frame.dim,
                              grayscale: frame.grayscale, active: true,
                              phaseName: frame.name,
                              nextEventName: next.0, nextEventTime: next.1)
            }
            previousWarmth = frame.warmth
            previousDim = frame.dim
        }
        return day   // unreachable: the loop always returns for now within [start, end)
    }

    // MARK: - Window selection

    /// The timeline whose window contains (or is next to contain) `now`.
    /// An evening "window" runs from that day's sunset to the next day's sunrise —
    /// trying yesterday's window first covers the hours between midnight and sunrise.
    public static func around(_ now: Date,
                              latitude: Double, longitude: Double,
                              bedtimeMinutes: Int,
                              timeZone: TimeZone = .current) -> CircadianTimeline {
        for dayOffset in [-1, 0] {
            let day = now.addingTimeInterval(TimeInterval(dayOffset) * 86400)
            let timeline = window(for: day, latitude: latitude, longitude: longitude,
                                  bedtimeMinutes: bedtimeMinutes, timeZone: timeZone)
            if now < timeline.end { return timeline }
        }
        // Unreachable in practice (today's window always ends tomorrow morning).
        return window(for: now, latitude: latitude, longitude: longitude,
                      bedtimeMinutes: bedtimeMinutes, timeZone: timeZone)
    }

    /// The wind-down window for the evening of `day`: its sunset through the next
    /// morning's sunrise, with the bedtime placed on the correct side of midnight.
    public static func window(for day: Date,
                              latitude: Double, longitude: Double,
                              bedtimeMinutes: Int,
                              timeZone: TimeZone = .current) -> CircadianTimeline {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: day)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // Polar day/night fallback: a fixed, sane evening (sunset 19:00 / sunrise 07:00).
        let sunset = SolarCalculator.sunTimes(on: day, latitude: latitude,
                                              longitude: longitude, timeZone: timeZone)?
            .sunset ?? dayStart.addingTimeInterval(19 * 3600)
        let sunrise = SolarCalculator.sunTimes(on: nextDay, latitude: latitude,
                                               longitude: longitude, timeZone: timeZone)?
            .sunrise ?? nextDay.addingTimeInterval(7 * 3600)

        // Bedtimes before noon (e.g. 00:30) belong to the morning after this sunset.
        let bedtimeDay = bedtimeMinutes < 12 * 60 ? nextDay : dayStart
        let bedtime = bedtimeDay.addingTimeInterval(TimeInterval(bedtimeMinutes) * 60)

        return CircadianTimeline(sunset: sunset, bedtime: bedtime, sunrise: sunrise)
    }
}
