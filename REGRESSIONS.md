# DuskMode — Fixed-Bug Register (regression guard)

> **Claude: read this file together with CLAUDE.md at the start of every session,
> and RE-READ it before touching any engine or the apply path.** Every bug here was
> already fixed at least once. Each entry states the INVARIANT that must keep
> holding and how to re-check it. Before claiming any change "done", walk this
> list and confirm none of the invariants is violated by the diff.
>
> **Rule: every time a bug is fixed, add an entry here (numbered, newest last)
> in the same commit as the fix.**

---

## 1. ⌘Tab / app-switch overlay flash  ⚠️ regressed once already
- **Symptom:** screen shows unfiltered for a split second when switching apps
  (⌘Tab); the dim/tint "catches up" a few ms later.
- **Root cause:** re-ordering an already-visible overlay window
  (`orderFrontRegardless()`) makes the compositor drop it for a frame. First
  caused by a `didActivateApplication` reorder observer (removed 2026-07-06
  afternoon). **Reintroduced by Phase 2:** the 30 s schedule tick re-ran
  `OverlayEngine.apply()` which called `orderFrontRegardless()` every tick
  (fixed 2026-07-06 night).
- **Invariant:** while an overlay window is visible, ticks/re-applies may ONLY
  change its `backgroundColor` (and skip even that when unchanged). Order front
  exclusively on first show, on Space change (`activeSpaceDidChangeNotification`
  — transitions are animated so it's invisible), and after rebuilds (display
  change / wake). NEVER add an app-activation observer that reorders windows.
- **Re-check:** schedule ON with dim > 0 → ⌘Tab rapidly between apps → no flash.
  Manual dim = 0 does NOT exercise this (no overlay window exists then).

## 2. Grayscale silently doing nothing (`CGDisplayForceToGray`)
- **Symptom:** grayscale toggle appears to work (getter flips) but screen stays
  in colour.
- **Root cause:** `CGDisplayForceToGray` is vestigial on macOS 15 — the flag
  stores but the compositor ignores it.
- **Invariant:** grayscale = `UAGrayscaleSetEnabled` (private, dlsym) primary,
  MA-pref write fallback, CGEvent ⌥⌘F5 last. Never "upgrade" back to
  force-to-gray or any silent path — all were proven dead (see CLAUDE.md).
- **Re-check:** toggle grayscale in popover → screen actually desaturates.

## 3. Grayscale "Colour Filters" bezel — UNAVOIDABLE, not a bug
- Every silent route was live-tested and is a dead end (force-to-gray no-op,
  SkyLight filter whitelist rejects desaturation, pref-write-without-notify
  still triggers AccessibilityVisualsAgent). **Do not spend time re-fixing;
  do not swap methods to hide it.** The popover caption sets expectation.

## 4. Grayscale bezel spam from the schedule
- **Symptom:** macOS Colour Filters bezel popping every 30 s while the schedule
  runs.
- **Invariant:** schedule-driven grayscale is EDGE-TRIGGERED
  (`scheduledGrayscale` in AppDelegate): system state is touched only when the
  desired state *changes*. Never call `setGrayscale` unconditionally per tick.
- **Re-check:** schedule ON in a grayscale phase → bezel appears once, not
  repeatedly.

## 5. Reddish-film tint instead of warm light
- **Symptom:** colour looks like a translucent red film; blacks lifted
  (f.lux comparison).
- **Invariant:** colour rides GAMMA (`CGSetDisplayTransferByFormula`) whenever
  available; the overlay carries colour only as fallback when gamma fails.
  Both paths share `ColorTemperature.swift`. Never route colour through the
  overlay while gamma works.
- **Re-check:** with warmth up, blacks stay black; screenshots show no tint.

## 6. Duplicate menu-bar icons / stale process after rebuild
- **Symptom:** old copy keeps running; two moon icons; old code still active.
- **Invariant:** `build.sh` pkills the running copy before every build. Never
  launch a new build without it (or verify with `ps` that one process runs).

## 7. Slider touch during schedule causing a visual jump
- **Invariant:** touching master/sliders while the schedule runs ADOPTS the
  schedule's current values into manual prefs *first*, then disables the
  schedule (seamless handoff). Order matters — see `handOffToManualIfScheduled`
  / `masterChanged` in PopoverViewController.
- **Re-check:** drag a slider mid-schedule → no flicker, schedule switch goes off.

## 8. Schedule fighting manual prefs (feedback loop)
- **Invariant:** `CircadianEngine` NEVER writes `PreferencesStore` — targets go
  straight to the engines via `applyScheduleTarget`. Writing prefs from the
  schedule would re-trigger `preferencesChanged` in a loop.

---

### Standing verification checklist (run after ANY engine/apply-path change)
1. `swift run DuskModeSelfTest` — all green.
2. `./build.sh release run` — single process, icon appears.
3. Manual mode: master on, warmth up → warm, blacks black; dim up → darkens.
4. Schedule mode: switch on → status line correct; ⌘Tab flash check (#1);
   grayscale phase → one bezel only (#4).
5. Quit app → screen returns fully to normal.
