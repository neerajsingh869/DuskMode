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
// Nominal ladder: Sunset 19:10, Warm 20:30, Grayscale 21:00, Red 22:00, Bedtime 23:00.
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
    // 19:50 — past the 30-min sunset ramp, before Warm.
    let target = typical.target(at: time(19, 50))
    expect(target.active && target.phaseName == "Sunset", "19:50 is settled Sunset phase")
    expectEqual(target.warmth, ColorTemperature.warmth(forKelvin: 5000),
                accuracy: 0.001, "Sunset warmth = 5000 K")
    expectEqual(target.dim, 0.10, accuracy: 0.001, "Sunset dim = 10%")
    expect(!target.grayscale && target.nextEventName == "Warm",
           "Sunset: no grayscale, Warm next")
}

do {
    // Warm starts 20:30, ramp 25 min → halfway at 20:42:30.
    let halfway = time(20, 30).addingTimeInterval(12.5 * 60)
    let target = typical.target(at: halfway)
    let expected = (ColorTemperature.warmth(forKelvin: 5000)
                    + ColorTemperature.warmth(forKelvin: 3400)) / 2
    expect(target.phaseName == "Warm", "mid-ramp reports Warm phase")
    expectEqual(target.warmth, expected, accuracy: 0.002, "warmth interpolates halfway")
    expectEqual(target.dim, 0.15, accuracy: 0.002, "dim interpolates halfway")
}

do {
    expect(!typical.target(at: time(20, 59)).grayscale, "20:59 — grayscale still off")
    expect(typical.target(at: time(21, 1)).grayscale, "21:01 — grayscale flipped on")
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
    // An early bedtime squeezes the ladder but keyframes must stay strictly ordered.
    let squeezed = CircadianTimeline(sunset: time(19, 10),
                                     bedtime: time(20, 0),
                                     sunrise: time(5, 45, dayOffset: 1))
    for (a, b) in zip(squeezed.keyframes, squeezed.keyframes.dropFirst()) {
        expect(b.start >= a.start.addingTimeInterval(a.ramp),
               "squeezed ladder: \(b.name) starts after \(a.name)'s ramp")
    }
    expect(squeezed.end > squeezed.keyframes.last!.start,
           "squeezed ladder still ends after last keyframe")
}

do {
    // Late sunsets never delay the ladder past bedtime−3h.
    let lateSunset = CircadianTimeline(sunset: time(21, 30),
                                       bedtime: time(23, 0),
                                       sunrise: time(5, 45, dayOffset: 1))
    expect(lateSunset.keyframes[0].start == time(20, 0),
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
    expect(timeline.keyframes.last!.start == time(0, 30, dayOffset: 1),
           "00:30 bedtime keyframe lands next morning")
    expect(target.active && target.phaseName == "Warm",
           "22:00 with 00:30 bedtime is the Warm phase (2.5 h out)")
}

// MARK: - Verdict

if failures == 0 {
    print("\nAll self-tests passed.")
    exit(0)
} else {
    print("\n\(failures) self-test(s) FAILED.")
    exit(1)
}
