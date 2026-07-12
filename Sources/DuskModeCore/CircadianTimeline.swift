import Foundation

/// The pure maths of one evening's wind-down: builds the anchor ladder from
/// sunset/bedtime/sunrise and answers "what should the screen look like right now".
/// No AppKit, no timers, no I/O — CircadianEngine drives it, unit tests exercise it.
///
/// The evening is one CONTINUOUS slide (no plateaus): warmth/dim move linearly from
/// each anchor straight to the next, so the screen passes through every research
/// value at its anchored time and never changes perceptibly between two 30 s ticks.
/// Anchor values come straight from research/notes.md:
/// - Sunset  (sunset + 30 min ramp-in)  5000 K, dim  0%  — colour-only dusk; the room
///                                                          is still bright, dim comes later
/// - Warm    (bedtime − 2.5 h)          3400 K, dim 20%  — DLMO window opens 2–3 h before bed
/// - Dusk    (bedtime − 2 h)            2700 K, dim 30%  — wind-down deepens
/// - Red     (bedtime − 1 h)            1900 K, dim 50%  — 620–670 nm safe tail
/// - Bedtime (at bedtime)               1900 K, dim 80%  — toward the ≤1 lux goal
/// Grayscale is binary (can't be interpolated): it flips ON at bedtime − 1.5 h —
/// a separate edge, deliberately decoupled from the colour anchors.
/// Everything reverts at sunrise.
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

    public struct Anchor {
        public let time: Date              // warmth/dim reach exactly these values here
        public let warmth: Double
        public let dim: Double
        public let name: String
    }

    public let start: Date          // activation — the slide begins here from (0, 0)
    public let anchors: [Anchor]    // Sunset … Bedtime, strictly increasing times
    public let grayscaleStart: Date // grayscale ON from here until sunrise
    public let end: Date            // sunrise — everything off

    public init(sunset: Date, bedtime: Date, sunrise: Date) {
        struct Preset {
            let nominal: Date
            let kelvin: Double, dim: Double, name: String
        }
        // Sunset never starts later than 3h before bed, so short evenings
        // (early bedtimes, late summer sunsets) still get a full wind-down.
        let sunsetStart = min(sunset, bedtime.addingTimeInterval(-3 * 3600))
        let presets = [
            Preset(nominal: sunsetStart.addingTimeInterval(30 * 60),
                   kelvin: 5000, dim: 0.00, name: "Sunset"),
            Preset(nominal: bedtime.addingTimeInterval(-2.5 * 3600),
                   kelvin: 3400, dim: 0.20, name: "Warm"),
            Preset(nominal: bedtime.addingTimeInterval(-2 * 3600),
                   kelvin: 2700, dim: 0.30, name: "Dusk"),
            Preset(nominal: bedtime.addingTimeInterval(-1 * 3600),
                   kelvin: 1900, dim: 0.50, name: "Red"),
            Preset(nominal: bedtime,
                   kelvin: 1900, dim: 0.80, name: "Bedtime")
        ]
        // Keep anchors strictly ordered (≥ 5 min apart), so a squeezed evening
        // degrades gracefully instead of anchors landing on top of each other.
        start = sunsetStart
        var frames: [Anchor] = []
        for preset in presets {
            var time = max(preset.nominal, sunsetStart)
            if let previous = frames.last {
                time = max(time, previous.time.addingTimeInterval(5 * 60))
            }
            frames.append(Anchor(time: time,
                                 warmth: ColorTemperature.warmth(forKelvin: preset.kelvin),
                                 dim: preset.dim, name: preset.name))
        }
        anchors = frames
        // Sunrise must land after the ladder even in degenerate inputs.
        end = max(sunrise, frames.last!.time.addingTimeInterval(30 * 60))
        // Grayscale edge: 1.5 h before bed, clamped inside the active window.
        let nominalGray = bedtime.addingTimeInterval(-1.5 * 3600)
        grayscaleStart = min(max(nominalGray, frames[0].time), frames.last!.time)
    }

    public func target(at now: Date) -> Target {
        let day = Target(warmth: 0, dim: 0, grayscale: false, active: false,
                         phaseName: "Day",
                         nextEventName: anchors[0].name,
                         nextEventTime: start)
        guard now >= start, now < end else { return day }

        // Continuous piecewise-linear slide through (start, 0, 0) and every anchor;
        // after the last anchor the deepest values hold until sunrise.
        var previousTime = start
        var previousWarmth = 0.0
        var previousDim = 0.0
        var warmth = anchors.last!.warmth
        var dim = anchors.last!.dim
        for anchor in anchors {
            if now < anchor.time {
                let span = anchor.time.timeIntervalSince(previousTime)
                let fraction = span > 0 ? now.timeIntervalSince(previousTime) / span : 1
                warmth = previousWarmth + (anchor.warmth - previousWarmth) * fraction
                dim = previousDim + (anchor.dim - previousDim) * fraction
                break
            }
            previousTime = anchor.time
            previousWarmth = anchor.warmth
            previousDim = anchor.dim
        }

        // Phase = the segment we're in. "Sunset" covers activation through the Warm
        // anchor (the ramp-in plus the first slide); each later anchor names the
        // segment it starts.
        var phase = anchors[0].name
        for anchor in anchors.dropFirst() where now >= anchor.time {
            phase = anchor.name
        }

        // Next event = the earliest upcoming boundary: a colour anchor, the
        // grayscale edge, or sunrise.
        var events: [(name: String, time: Date)] =
            anchors.dropFirst().map { ($0.name, $0.time) }
        events.append(("Grayscale", grayscaleStart))
        events.append(("Sunrise", end))
        events.sort { $0.time < $1.time }
        let next = events.first { $0.time > now }

        return Target(warmth: warmth, dim: dim,
                      grayscale: now >= grayscaleStart, active: true,
                      phaseName: phase,
                      nextEventName: next?.name, nextEventTime: next?.time)
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
