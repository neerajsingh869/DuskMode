import Foundation
import DuskModeCore

// Self-test runner for DuskModeCore. This machine has only Command Line Tools
// (no Xcode), which ship neither XCTest nor Swift Testing — so the tests are a
// plain executable:   swift run DuskModeSelfTest   (exits non-zero on failure).

var failures = 0

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("  ok   \(message)")
    } else {
        failures += 1
        print("  FAIL \(message)  (main.swift:\(line))")
    }
}

func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double,
                 _ message: String, line: Int = #line) {
    expect(abs(actual - expected) <= accuracy,
           "\(message) — got \(actual), want \(expected) ± \(accuracy)", line: line)
}

// MARK: - Shared helpers

func calendar(_ timeZone: TimeZone) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    return cal
}

func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, in tz: TimeZone) -> Date {
    calendar(tz).date(from: DateComponents(
        year: year, month: month, day: dayOfMonth, hour: 12))!
}

func minutesIntoDay(_ date: Date, in tz: TimeZone) -> Double {
    let c = calendar(tz).dateComponents([.hour, .minute], from: date)
    return Double(c.hour! * 60 + c.minute!)
}

// MARK: - SolarCalculator

print("SolarCalculator")

do {
    // London, 2026-06-21 (summer solstice): sunset ≈ 21:21 BST, sunrise ≈ 04:43 BST.
    let tz = TimeZone(identifier: "Europe/London")!
    if let times = SolarCalculator.sunTimes(on: day(2026, 6, 21, in: tz),
                                            latitude: 51.5074, longitude: -0.1278,
                                            timeZone: tz) {
        expectEqual(minutesIntoDay(times.sunset, in: tz), Double(21 * 60 + 21),
                    accuracy: 10, "London solstice sunset ≈ 21:21 BST")
        expectEqual(minutesIntoDay(times.sunrise, in: tz), Double(4 * 60 + 43),
                    accuracy: 10, "London solstice sunrise ≈ 04:43 BST")
    } else {
        expect(false, "London solstice must have sun times")
    }
}

do {
    // New Delhi, 2026-07-06: sunset ≈ 19:22 IST.
    let tz = TimeZone(identifier: "Asia/Kolkata")!
    if let times = SolarCalculator.sunTimes(on: day(2026, 7, 6, in: tz),
                                            latitude: 28.6139, longitude: 77.2090,
                                            timeZone: tz) {
        expectEqual(minutesIntoDay(times.sunset, in: tz), Double(19 * 60 + 22),
                    accuracy: 10, "Delhi 6 July sunset ≈ 19:22 IST")
        expect(times.sunrise < times.solarNoon && times.solarNoon < times.sunset,
               "sunrise < solar noon < sunset")
    } else {
        expect(false, "Delhi July must have sun times")
    }
}

do {
    // On the equator, day length stays ~12 h all year (within ~15 min).
    let tz = TimeZone(identifier: "America/Guayaquil")!
    for month in [1, 4, 7, 10] {
        if let times = SolarCalculator.sunTimes(on: day(2026, month, 15, in: tz),
                                                latitude: 0.0, longitude: -78.5,
                                                timeZone: tz) {
            let length = times.sunset.timeIntervalSince(times.sunrise) / 60
            expectEqual(length, 12 * 60, accuracy: 15,
                        "equator day length ≈ 12 h (month \(month))")
        } else {
            expect(false, "equator must have sun times (month \(month))")
        }
    }
}

do {
    // Longyearbyen (78°N) mid-winter: the sun never rises — must return nil.
    let tz = TimeZone(identifier: "Arctic/Longyearbyen")!
    expect(SolarCalculator.sunTimes(on: day(2026, 12, 21, in: tz),
                                    latitude: 78.2232, longitude: 15.6267,
                                    timeZone: tz) == nil,
           "polar night returns nil")
}

// MARK: - CircadianTimeline

print("CircadianTimeline")

let tz = TimeZone(identifier: "Asia/Kolkata")!

func time(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
    calendar(tz).date(from: DateComponents(
        year: 2026, month: 7, day: 6 + dayOffset, hour: hour, minute: minute))!
}

// A typical evening: sunset 19:10, bedtime 23:00, sunrise 05:45 next day.
// Anchors: Sunset 19:40 (ramp-in from 19:10), Warm 20:30, Dusk 21:00, Red 22:00,
// Bedtime 23:00. Grayscale edge at 21:30 (bedtime − 1.5 h).
let typical = CircadianTimeline(sunset: time(19, 10),
                                bedtime: time(23, 0),
                                sunrise: time(5, 45, dayOffset: 1))

do {
    let target = typical.target(at: time(15, 0))
    expect(!target.active && !target.grayscale, "3 pm is inactive daytime")
    expect(target.nextEventName == "Sunset" && target.nextEventTime == time(19, 10),
           "next event from daytime is Sunset 19:10")
}

do {
    // 19:40 — the Sunset anchor: exactly 5000 K and (new) ZERO dim — colour-only dusk.
    let target = typical.target(at: time(19, 40))
    expect(target.active && target.phaseName == "Sunset", "19:40 is the Sunset anchor")
    expectEqual(target.warmth, ColorTemperature.warmth(forKelvin: 5000),
                accuracy: 0.001, "Sunset anchor warmth = 5000 K")
    expectEqual(target.dim, 0.0, accuracy: 0.001, "Sunset anchor dim = 0% (colour first)")
    expect(!target.grayscale && target.nextEventName == "Warm",
           "Sunset: no grayscale, Warm next")
}

do {
    // CONTINUOUS slide, no plateau: 20:05 is halfway from Sunset (19:40) to Warm
    // (20:30) — values must already be en route, not parked at the anchor.
    let target = typical.target(at: time(20, 5))
    let expected = (ColorTemperature.warmth(forKelvin: 5000)
                    + ColorTemperature.warmth(forKelvin: 3400)) / 2
    expect(target.phaseName == "Sunset", "20:05 still reports the Sunset segment")
    expectEqual(target.warmth, expected, accuracy: 0.002,
                "no plateau — warmth halfway to Warm at the segment midpoint")
    expectEqual(target.dim, 0.10, accuracy: 0.002, "dim halfway to Warm's 20%")
}

do {
    // 20:45 — halfway from Warm (20:30) to Dusk (21:00).
    let target = typical.target(at: time(20, 45))
    let expected = (ColorTemperature.warmth(forKelvin: 3400)
                    + ColorTemperature.warmth(forKelvin: 2700)) / 2
    expect(target.phaseName == "Warm", "20:45 is the Warm segment")
    expectEqual(target.warmth, expected, accuracy: 0.002, "warmth slides Warm → Dusk")
    expectEqual(target.dim, 0.25, accuracy: 0.002, "dim slides 20% → 30%")
}

do {
    // The whole evening is monotonic: warmth and dim never move backwards.
    var last = typical.target(at: time(19, 10))
    var monotonic = true
    for minutes in stride(from: 1, through: 4 * 60, by: 1) {
        let target = typical.target(at: time(19, 10).addingTimeInterval(Double(minutes) * 60))
        if target.warmth < last.warmth - 1e-9 || target.dim < last.dim - 1e-9 {
            monotonic = false
        }
        last = target
    }
    expect(monotonic, "warmth/dim are monotonically non-decreasing all evening")
}

do {
    // Grayscale edge at bedtime − 1.5 h = 21:30, decoupled from the colour anchors.
    expect(!typical.target(at: time(21, 29)).grayscale, "21:29 — grayscale still off")
    expect(typical.target(at: time(21, 31)).grayscale, "21:31 — grayscale flipped on")
    let beforeEdge = typical.target(at: time(21, 10))
    expect(beforeEdge.phaseName == "Dusk" && beforeEdge.nextEventName == "Grayscale"
           && beforeEdge.nextEventTime == time(21, 30),
           "21:10 is Dusk with Grayscale announced next at 21:30")
}

do {
    // 23:30 — past the bedtime ramp: the deepest state.
    let target = typical.target(at: time(23, 30))
    expect(target.phaseName == "Bedtime", "23:30 is Bedtime phase")
    expectEqual(target.warmth, 1.0, accuracy: 0.001, "Bedtime warmth = 1900 K (max)")
    expectEqual(target.dim, 0.80, accuracy: 0.001, "Bedtime dim = 80%")
    expect(target.grayscale && target.nextEventName == "Sunrise",
           "Bedtime: grayscale on, Sunrise next")
}

do {
    expect(typical.target(at: time(3, 0, dayOffset: 1)).active, "3 am still active")
    expect(!typical.target(at: time(6, 0, dayOffset: 1)).active, "6 am (post-sunrise) off")
}

do {
    // An early bedtime squeezes the ladder but anchors must stay strictly ordered
    // and the grayscale edge must stay inside the active window.
    let squeezed = CircadianTimeline(sunset: time(19, 10),
                                     bedtime: time(20, 0),
                                     sunrise: time(5, 45, dayOffset: 1))
    for (a, b) in zip(squeezed.anchors, squeezed.anchors.dropFirst()) {
        expect(b.time > a.time, "squeezed ladder: \(b.name) is after \(a.name)")
    }
    expect(squeezed.end > squeezed.anchors.last!.time,
           "squeezed ladder still ends after the last anchor")
    expect(squeezed.grayscaleStart >= squeezed.start
           && squeezed.grayscaleStart <= squeezed.anchors.last!.time,
           "squeezed grayscale edge stays inside the window")
}

do {
    // Late sunsets never delay the ladder past bedtime−3h.
    let lateSunset = CircadianTimeline(sunset: time(21, 30),
                                       bedtime: time(23, 0),
                                       sunrise: time(5, 45, dayOffset: 1))
    expect(lateSunset.start == time(20, 0),
           "late sunset capped at bedtime − 3 h")
}

// MARK: - Window selection

print("Window selection")

do {
    // 02:00 — must land inside yesterday's window (Bedtime phase), not "Day".
    let target = CircadianTimeline.around(time(2, 0),
                                          latitude: 28.6139, longitude: 77.2090,
                                          bedtimeMinutes: 23 * 60,
                                          timeZone: tz).target(at: time(2, 0))
    expect(target.active && target.phaseName == "Bedtime",
           "2 am uses yesterday's evening (Bedtime phase)")
}

do {
    let target = CircadianTimeline.around(time(14, 0),
                                          latitude: 28.6139, longitude: 77.2090,
                                          bedtimeMinutes: 23 * 60,
                                          timeZone: tz).target(at: time(14, 0))
    expect(!target.active && target.nextEventName == "Sunset",
           "2 pm is daytime with Sunset next")
    if let next = target.nextEventTime {
        expect(next > time(18, 30) && next < time(20, 0),
               "next Sunset lands in the evening (Delhi ≈ 19:22)")
    } else {
        expect(false, "daytime target must know the next event time")
    }
}

do {
    // A bedtime after midnight (00:30) belongs to the *next* calendar morning.
    let timeline = CircadianTimeline.around(time(22, 0),
                                            latitude: 28.6139, longitude: 77.2090,
                                            bedtimeMinutes: 30,
                                            timeZone: tz)
    let target = timeline.target(at: time(22, 0))
    expect(timeline.anchors.last!.time == time(0, 30, dayOffset: 1),
           "00:30 bedtime anchor lands next morning")
    expect(target.active && target.phaseName == "Warm",
           "22:00 with 00:30 bedtime is the Warm segment (2.5 h out)")
}

print("ColorCriticalApps")

do {
    expect(ColorCriticalApps.matches("com.figma.Desktop"), "Figma is colour-critical")
    expect(ColorCriticalApps.matches("com.adobe.PremierePro.24"), "versioned Premiere Pro matches its family")
    expect(ColorCriticalApps.matches("com.seriflabs.affinityphoto2"), "Affinity Photo 2 matches its family")
    expect(!ColorCriticalApps.matches("com.apple.Safari"), "Safari is not colour-critical")
    expect(!ColorCriticalApps.matches("com.adobe.Photoshop.helper"), "exact entries don't swallow helper IDs")

    let installed = ["com.figma.Desktop": "Figma", "com.adobe.Photoshop": "Adobe Photoshop",
                     "com.apple.Safari": "Safari"]
    let first = ColorCriticalApps.toAutoAdd(installed: installed, alreadyPaused: [], previouslyAutoAdded: [])
    expect(Set(first.keys) == ["com.figma.Desktop", "com.adobe.Photoshop"],
           "first launch adds every installed colour-critical app, nothing else")
    // Regression guard: the user removed Figma with ✕ — it must not come back.
    let afterRemoval = ColorCriticalApps.toAutoAdd(installed: installed,
                                                   alreadyPaused: ["com.adobe.Photoshop"],
                                                   previouslyAutoAdded: ["com.figma.Desktop", "com.adobe.Photoshop"])
    expect(afterRemoval.isEmpty, "an app removed by the user is never re-added")
}

// MARK: - Verdict

if failures == 0 {
    print("\nAll self-tests passed.")
    exit(0)
} else {
    print("\n\(failures) self-test(s) FAILED.")
    exit(1)
}
