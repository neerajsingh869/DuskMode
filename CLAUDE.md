# DuskMode — Project State & Continuity

> **Claude: read this file FIRST in every new session, then `PRIVATE.md` if it exists
> (local-only working notes: business decisions and the session log, gitignored and never
> pushed), then `REGRESSIONS.md` (the fixed-bug register).** Every fixed bug gets an
> invariant entry in REGRESSIONS.md in the same commit as the fix, and its checklist must
> be walked before any engine or apply-path change is called done.
>
> **This repo is PUBLIC.** Only product knowledge goes in tracked files: architecture,
> decisions about the app and site, status. Business strategy, budget, accounts, personal
> notes and session logs go in `PRIVATE.md`. Design mockups live in `design/`, which is
> also gitignored.

---

## What it is
A native macOS **menu bar app** that automates a science-backed evening wind-down on one
timeline tied to local sunset and the user's bedtime: warmth (blue and green cut), dimming
below the lowest hardware brightness, and system grayscale before bed.
Bundle ID `app.duskmode`. Version 1.0. Website https://neerajsingh869.github.io/DuskMode/.

## Rules for this project
1. **Research before building any feature.** Cite peer-reviewed studies in
   `research/citations.json`.
2. **No fragile OS internals.** Public APIs only, with one documented exception
   (grayscale, below), quarantined in one file with fallbacks.
3. **Native Swift + AppKit only.** No Electron, no web views, <1% CPU idle.
4. **No third-party code** in the app (the solar calculator etc. are self-written).
5. **Free and open source (MIT).**

## Architecture (why it survives macOS updates)
| Layer | Technique | Notes |
|---|---|---|
| Colour (warmth) | `CGSetDisplayTransferByFormula` gamma, blackbody Kelvin→RGB (`DuskModeCore/ColorTemperature.swift`) | f.lux's method; blacks stay black; WindowServer restores gamma on exit; invisible to screenshots and screen sharing (verified with ScreenCaptureKit) |
| Dimming | Same gamma call, all channels × (1 − dim×0.92) | No window, so it can't flash on app switch (REGRESSIONS #9) |
| Fallback | Overlay `NSWindow` (`OverlayEngine`) | Only when the gamma API is unavailable (capability probed once at startup, never latched off by transient failures, #10) |
| Grayscale | `UAGrayscaleSetEnabled` via dlsym (`GrayscaleEngine.swift`), MA-pref then ⌥⌘F5 fallbacks | The only private symbol. The ~1 s "Colour Filters" bezel is unavoidable on macOS 15; every silent route was tested and fails (CGDisplayForceToGray is vestigial, SkyLight rejects desaturation filters, pref writes still trigger the agent). Don't re-litigate. |

**Grayscale is applied after warmth (observed 2026-09-25 on an M4, macOS 15).** With
grayscale on, the screen is plain neutral gray and Kelvin has no visible effect; only
dimming still shows. So from the grayscale edge (bedtime − 1.5 h) the blue cut is undone
and dimming alone reduces light. Gamma readbacks still show warm values, and screenshots
can't show either effect, so only eyes on the panel settle this. **Open decision (not
changed yet):** whether the app's grayscale phase should change because of this.

**Single apply choke point:** `AppDelegate.applyEffectiveState()` owns all screen state.
Priority: Emergency Color → app pause → mode (off / manual / auto).

## Settled product decisions (don't re-litigate without new evidence)
- **Mode** is one control: Off | Manual | Auto (#16). Sliders exist only in Manual (#20).
- **Timeline** is a continuous piecewise-linear slide (no plateaus). Anchors, values
  reached AT each time: Sunset (min(sunset, B−3h) + 30 min) 5000 K / 0% · Warm (B−2.5h)
  3400 K / 20% · Dusk (B−2h) 2700 K / 30% · Red (B−1h) 1900 K / 50% · Bedtime (B)
  1900 K / 80%, held until sunrise. Grayscale edge at B−1.5h, decoupled from the colour
  anchors. Default bedtime 23:00.
- **Grayscale** is both automatic in Auto and an always-available manual toggle.
  Schedule-owned grayscale is released on leaving Auto; a hand-toggled one is never swept
  by mode changes (#14–#17).
- **App pause:** a paused app in front drops warmth and grayscale and KEEPS dimming (#18).
  Colour-critical apps (Figma, Photoshop, Sketch, Lightroom, Final Cut…, see
  `DuskModeCore/ColorCriticalApps.swift`) are added to the pause list automatically, once
  each; a removal sticks (#23). Any other app is added with the popover's "Pause for [app]"
  switch.
- **Emergency Color** ⌥⌘C (Carbon hotkey, no Accessibility permission): 60 s full colour,
  auto-revert; only available when something is actually filtering (#12).
- **Launch at login:** `SMAppService.mainApp`, registered once silently on first launch.
  No toggle in the app; opt out in System Settings → Login Items (#22).
- **Location:** one CoreLocation fix, cached; time-zone fallback. Zero network requests,
  ever. No IP geolocation.
- **Settings window** (right-click the menu bar icon): General (read-only info), Timeline
  (visualise only, not editable), Science (renders `citations.json`, counter-evidence kept).
- Deepest keyframe stays 1900 K for now (softening deferred until asked).

## Science → numbers (full detail in `research/notes.md`)
- Blue melatonin peak ~464–480 nm (strong). Green ~555 nm matters early in the evening
  (moderate). Red 620–670 nm is the safe tail (moderate).
- ~6 lux → 50% melatonin suppression; brightness matters more than colour (Nagare 2019,
  Cajochen 2022). Targets (Brown 2022): evening ≤10 lux, sleep ≤1 lux.
- DLMO ≈ 2–3 h before sleep, so the wind-down starts 2–3 h before bedtime.
- Grayscale cut phone use ~40 min/day (emerging evidence; label it honestly).
- Counter-evidence kept visible: Cochrane 2023 found no clear benefit from blue-blocking
  glasses (weak filters, untimed).

## Structure
```
DuskMode/
├── CLAUDE.md, REGRESSIONS.md, README.md, LICENSE, install.sh
├── Package.swift, build.sh            # SwiftPM (no Xcode needed); ./build.sh release run
├── research/                          # citations.json (7 topics / 17 studies), notes.md
├── site/                              # the website: static HTML/CSS/JS, source of truth
├── .github/workflows/pages.yml        # deploys site/ to GitHub Pages on push to main
└── Sources/
    ├── DuskModeCore/                  # pure logic: ColorTemperature, SolarCalculator,
    │                                  # CircadianTimeline, ColorCriticalApps
    ├── DuskMode/                      # the app: App/, Engines/, UI/, Models/, Utilities/
    └── DuskModeSelfTest/              # swift run DuskModeSelfTest (50 checks, exit≠0 on fail)
```
This machine has Command Line Tools only (no XCTest), so tests are the self-test
executable. Run it after touching anything in DuskModeCore. Env: macOS 15.7.3, Apple M4.

## Distribution
- Unsigned (ad-hoc) for now. Primary install is `install.sh` via `curl | bash` (curl
  downloads aren't quarantined, so there's no Gatekeeper block); it pulls
  `releases/latest/download/DuskMode.zip`. Fallback is `DuskMode.dmg` plus the Open Anyway
  steps. Test the installer with `DUSKMODE_INSTALL_DIR=<dir> DUSKMODE_NO_OPEN=1`.
- Release packaging: `./build.sh release`, then `ditto -c -k --keepParent DuskMode.app
  DuskMode.zip`, and `hdiutil create` a UDZO dmg (app + /Applications symlink). Upload both
  with `gh release create`.
- Website: `site/index.html` (approved design, Round 5 of the landing-page design rounds;
  every section after the hero is a scroll sequence driven by the real timeline maths;
  grayscale is always rendered last, as neutral gray). Edit `site/` directly. Pushes to
  `main` redeploy Pages.

## Phases
- ✅ 0 Science · ✅ 1 Core layers · ✅ 2 Circadian timeline · ✅ 3 Intentionality
  (Emergency Color, app pause, hotkey)
- 🟡 4 Polish: launch at login ✅, settings window ✅, CPU audit (0.0% idle) ✅,
  screen-share invisibility ✅. Open: external-monitor and full-screen live checks,
  onboarding.
- ✅ 5 Public release: site live, repo public, v1.0.0 released (2026-09-25).

## CURRENT STATUS / NEXT ACTION
v1.0 is public. Open items:
1. Decide whether the grayscale phase should change, given it undoes the blue cut.
2. Replace the drawn "Open Anyway" prompt on the site with real screenshots.
3. External-monitor and full-screen live verification; onboarding.
