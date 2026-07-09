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

## 9. Brightness flash on app switch whenever dim > 0
- **Symptom:** with any dimming active, switching apps briefly shows full
  brightness; the dim "catches up" a few ms later. (Warmth never flashed —
  that was the clue.)
- **Root cause:** dim was an overlay `NSWindow`, and windows participate in
  app-switch compositing, so the dim layer can lag a frame. Gamma isn't a
  window and physically cannot flash. Entry #1's fix removed *our* churn but
  couldn't remove the window itself.
- **Fix (2026-07-06 ~20:00):** dim folded into GammaEngine — all three channel
  maxima scaled by `1 − dim×0.92` (mathematically identical to the black
  overlay). On working-gamma hardware NO overlay window exists at all.
- **Invariant:** on hardware where gamma works, BOTH colour and dim ride gamma;
  the overlay window exists only when `GammaEngine.isAvailable == false`.
  Never reintroduce a window-based layer on working-gamma hardware. Dim scale
  is floored at 8% output (`maxDimScale = 0.92`) so the screen stays usable.
- **Re-check:** master on, dim 50% → gamma readback maxima ≈ 0.54×multipliers
  AND zero DuskMode windows at layer 1000 in `CGWindowListCopyWindowInfo`.

## 10. Gamma silently latching OFF → app drops to the overlay for the session  ✅ Neeraj-confirmed fixed (2026-07-09)
- **Symptom:** intermittent — after the app had been running a while (across a
  sleep/wake or lid open), BOTH bugs #5 (reddish film) and #9 (app-switch flash)
  came back at once, independent of grayscale. Fresh launch was fine; "sometimes
  flashes, sometimes not" was the tell. Screenshots showed the tint (proof it was
  the OVERLAY — gamma is invisible to screencapture; verified live on this M4).
- **Root cause:** `GammaEngine.isAvailable` was a one-way latch. A
  `CGSetDisplayTransferByFormula` / `CGGetActiveDisplayList` call fails harmlessly
  for a moment when the display is asleep or mid-reconfiguration (lid close/open,
  monitor hot-plug). The old code flipped `isAvailable = false` on the FIRST such
  failure and never retried, so the whole app silently fell to the overlay
  (worse colour + flash) for the rest of the session. Gamma works fine on this M4
  — proven by driving a warm gamma directly (screen turned deep orange). It was
  the latch, not the hardware.
- **Fix (2026-07-07):** capability is decided ONCE at startup (`probeCapability`)
  and never revoked by transient runtime failures. A failed set just skips that
  cycle; `apply()` returns the fixed capability (not the per-call result) so a
  transient miss can't hand the frame to the overlay. Wake reassert retries at
  0.3/1.0/2.5 s so the tint reliably returns after lid open.
- **Invariant:** runtime set/list failures must NEVER flip `isAvailable`. Only the
  one-time startup probe may set it false. `apply()` returns capability, not
  per-call success. This is what actually keeps #5 and #9 fixed on this hardware.
- **Re-check:** master on, warmth up → gamma readback non-identity AND zero
  DuskMode overlay windows; sleep/wake (close+open lid) → tint returns, still no
  overlay window; ⌘Tab → no flash. Screenshot of a warm screen shows NO tint
  (proves gamma, not overlay, is rendering).

## 11. Grayscale scheduling + grayscale×warmth stacking — SETTLED design, not a bug
- **Grayscale is bundled in auto mode ON PURPOSE** (flips on ~2h before bedtime; timing is
  the whole point of the behavioral effect) and is ALSO an independent manual toggle when
  auto is off. Settled with Neeraj 2026-07-09 — do not "split grayscale out of auto".
- **Grayscale and warmth STACK and must both stay active together.** macOS composites the
  accessibility grayscale filter first, then applies the gamma LUT (warmth+dim) last, at
  scanout. Grayscale desaturates but does NOT reduce blue; warmth cuts blue on the
  resulting grays → warm sepia monochrome (behavioral + physiological, both reach panel).
- **Invariant:** warmth/colour must ride the FINAL output stage (gamma) so grayscale can't
  cancel the blue cut. Never introduce a colour/warmth layer that sits *before* the
  grayscale filter. GammaEngine and GrayscaleEngine stay independent; near bedtime both
  are on simultaneously (`applyScheduleTarget` applies gamma every tick + edge-toggles
  grayscale — see #4).
- **Re-check:** near-bedtime auto screen reads as a WARM/sepia gray, not a cold neutral
  gray (proves warmth is stacking on top of grayscale).

---

### Standing verification checklist (run after ANY engine/apply-path change)
1. `swift run DuskModeSelfTest` — all green.
2. `./build.sh release run` — single process, icon appears.
3. Manual mode: master on, warmth up → warm, blacks black; dim up → darkens.
4. Schedule mode: switch on → status line correct; ⌘Tab flash check (#1);
   grayscale phase → one bezel only (#4).
5. Quit app → screen returns fully to normal.
