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

## 12. Emergency Color override + the single apply choke point (Phase 3)
- **What it is:** a momentary "real colours NOW" override (default 60s, ⌥⌘C or the
  popover button) that suspends every filter, then auto-reverts to whatever mode was
  running (manual or schedule).
- **Invariant — one choke point:** all screen state flows through
  `AppDelegate.applyEffectiveState()`. It applies the Emergency branch FIRST (gamma
  `enabled:false`, overlay off, grayscale off) and returns; only when not active does it
  route to the schedule or the manual path. The 30s schedule tick calls it too
  (`onTarget → applyEffectiveState`), so an active override always wins over a tick.
  Never re-add a path that applies gamma/overlay/grayscale outside this method.
- **Invariant — override rides the same layers (not a new window):** Emergency Color
  restores full colour by driving GAMMA to identity, NOT by adding/removing an overlay
  window (keeps #9/#10 — zero DuskMode windows on working-gamma HW throughout the
  override and after revert).
- **Invariant — grayscale is saved/restored on the TRANSITIONS, not per tick:** grayscale
  is touched ONLY in `activateEmergencyColor` (record `grayscaleBeforeEmergency`, then turn
  off if it was on) and `cancelEmergencyColor` (restore). The emergency branch of
  `applyEffectiveState` must NOT touch grayscale, so the 30s schedule tick can't re-toggle
  it. The restore is UNCONDITIONAL (`if grayscaleBeforeEmergency { setGrayscale(true) }`) —
  it must NOT gate on a read-back of the current system state, because the UA getter can
  lag right after a set and the grayscale would be silently lost (the exact bug Neeraj hit
  2026-07-09). On exit `scheduledGrayscale` is set to `true` when grayscale was restored
  (else nil) so the schedule's edge-trigger stays consistent. Two bezels max per override
  (off on enter, back on exit) are expected, not a bug (see #3).
- **Invariant — availability gating:** Emergency Color is offered/activatable ONLY when
  something is actually filtering the screen — `isEmergencyColorAvailable` = colour active
  (manual master, or an active schedule) OR grayscale on. `toggleEmergencyColor` no-ops
  otherwise, and the popover button is disabled. Don't let the override arm on an
  unfiltered screen (there'd be nothing to restore, and cancel would fire a stray bezel).
- **Re-check:** (a) master off + schedule off + grayscale off → Emergency button disabled,
  ⌥⌘C does nothing. (b) master on + warmth up → gamma warm, 0 overlay windows; fire
  Emergency → gamma ≈ 1/1/1, 0 windows; wait out the timer (or tap again) → gamma back to
  the prior warm values. (c) grayscale ON + fire Emergency → grayscale off during; on
  revert → grayscale ON again. All three verified live 2026-07-09 via a temporary
  distributed-notification seam (removed before commit): warm 1.000/0.819/0.681 + gray ON
  → identity 1/1/1 + gray off → auto-revert 1.000/0.819/0.681 + gray ON; unfiltered toggle
  reported avail=false active=false. Carbon ⌥⌘C hotkey registration confirmed
  (RegisterEventHotKey == noErr); the physical keypress needs a human (keystroke injection
  is sandbox-blocked here).

## 13. Grayscale switch reads INTENT, not the momentary system state (Phase 3)
- **Symptom (Neeraj, 2026-07-09):** grayscale ON, then fire Emergency Color → the popover's
  grayscale switch flips to OFF during the override (then back ON when it ends). Confusing:
  the setting is intact, it's only *suspended* for real colour.
- **Root cause:** the switch mirrored the live system state
  (`grayscaleEngine.isGrayscaleEnabled()`), which the emergency genuinely turns off (#12).
- **Fix:** the switch reflects grayscale *intent*. `syncFromState` ORs in
  `grayscaleSuspendedForEmergency` (= emergency active AND `grayscaleBeforeEmergency`), so
  it stays ON while an emergency holds grayscale off. The SYSTEM grayscale is still really
  off during the override (#12 unchanged) — only the UI display changed.
- **Invariant:** UI switches show the user's intended setting, not a momentarily-suspended
  system state. Never regress the switch back to a bare `isGrayscaleEnabled()` read.
- **Re-check:** grayscale ON → fire Emergency → switch still shows ON (screen is colour);
  emergency ends → still ON, screen gray again.

## 14. Grayscale orphaned after the schedule/DuskMode is turned off (Phase 3)
- **Symptom (Neeraj, 2026-07-09):** near bedtime the schedule had turned grayscale on; he
  turned DuskMode off (master switch, which also turns the schedule off) → warmth reverted
  but the screen stayed GRAY. App "off" yet still altering the screen.
- **Root cause:** turning the schedule off in `preferencesChanged` ran `scheduledGrayscale =
  nil` but never released the grayscale the schedule had turned on.
- **Fix:** when the schedule turns off, if the schedule currently owned an on-grayscale
  (`scheduledGrayscale == true`) it is released (`setGrayscale(false)`), guarded by
  `isGrayscaleEnabled()` (edge-trigger, no stray bezel — #4) and skipped during an emergency
  (system grayscale is momentarily off then; `cancelEmergencyColor` restores correctly).
- **Design (settled with Neeraj 2026-07-09):** only SCHEDULE-owned grayscale is auto-released.
  Grayscale the user toggled BY HAND (`scheduledGrayscale != true`) is a peer setting and is
  left alone when the master/schedule turns off — it only goes off via its own toggle or app
  quit. Do not sweep manual grayscale on master-off.
- **Invariant:** stopping the schedule reverts ALL of the schedule's effects, grayscale
  included; manual grayscale is never touched by a master/schedule off.
- **Re-check:** schedule ON in the grayscale phase → master off → screen returns fully to
  normal (no warmth, no gray), one bezel. Separately: schedule OFF, toggle grayscale on by
  hand, master off → grayscale STAYS on.

## 15. Slider handoff near bedtime stripped grayscale (switch ON, screen colour)
- **Symptom (Neeraj, 2026-07-09):** schedule ON near bedtime → grayscale on (screen gray).
  He lowered the Dim slider to see better; the slider touch handed off to manual mode
  (schedule turned off) → the screen went back to COLOUR while the grayscale switch still
  read ON. "Grayscale is turned on but the screen is not grey."
- **Root cause:** two behaviours collided. The slider handoff
  (`handOffToManualIfScheduled`) turns the schedule off to move to manual, keeping the
  screen as-is. But turning the schedule off ran the #14 rule "schedule off → release the
  grayscale it owned" UNCONDITIONALLY, so the handoff stripped the grayscale the user
  wanted to keep. The popover switch, never re-synced after the handoff, still showed ON.
- **Fix:** the auto-grayscale release is gated on RETURNING TO NORMAL, not merely
  "schedule off". `releaseAutoGrayscaleIfIdle()` releases only when the screen is fully
  idle (`!scheduleEnabled && !masterEnabled && !emergency`). During a handoff
  `masterEnabled` stays on (filtering continues in manual) → grayscale is KEPT, and its
  ownership is TRANSFERRED to manual. Grayscale ownership is tracked by
  `grayscaleFromSchedule` (auto-owned = schedule/handoff-inherited) vs. a user hand-toggle
  (`setManualGrayscale` clears it → independent peer). The popover switch now reads
  grayscale INTENT from `prefs.grayscaleOn` (not the laggy live UA getter), so it can never
  show ON while the screen is colour.
- **Invariant:** auto-owned grayscale (schedule, or inherited by a slider handoff) is
  released ONLY when the screen returns fully to normal (idle); a hand-toggled grayscale is
  an independent peer, never swept by a master/schedule off. A slider handoff MUST keep
  grayscale and transfer its ownership to manual — never drop it. The grayscale switch
  reflects `prefs.grayscaleOn` (intent), OR'd with `grayscaleSuspendedForEmergency` (#13),
  never a bare live-getter read. All grayscale toggles from the popover route through
  `setManualGrayscale` (marks manual ownership + edge-guards the bezel).
- **Re-check:** schedule ON in the grayscale phase → drag the Dim slider → screen STAYS
  gray, schedule switch goes off, grayscale switch stays ON (consistent). Then master off →
  screen returns fully to normal (grayscale released). Separately: manual grayscale on by
  hand → master off → grayscale STAYS on (#14 second case still holds). Verified 2026-07-09
  via an injected recording-grayscale double driving the real preferencesChanged /
  releaseAutoGrayscaleIfIdle / applyScheduleTarget / setManualGrayscale (9 scenario checks
  incl. the exact bug A2, #14's C1, and manual-peer B2/D1 — all pass, no real bezels).

## 16. Off/Manual/Auto mode selector + grayscale released on LEAVING Auto (Phase 3)
- **Symptom (Neeraj, 2026-07-10):** turning off the Automatic schedule (while the DuskMode
  master switch was still on) left the schedule's grayscale ON. He expected leaving Auto to
  undo what Auto did, grayscale included. Also: the two peer switches (master + schedule)
  were confusing and were the root source of the grayscale-ownership bugs.
- **Fix — two parts:**
  1. **One `mode` (off/manual/auto)** replaces the master + schedule switches
     (`PreferencesStore.Mode`, migrates from the legacy bools once). The popover top is an
     `NSSegmentedControl`. `applyEffectiveState` switches on mode: auto → schedule, manual →
     `applyFilters(enabled:true,…)`, off → `applyFilters(enabled:false,…)`.
  2. **Grayscale released when LEAVING Auto**, not only when fully idle (supersedes #15's
     master-gate). In `preferencesChanged`, the `else if circadianEngine.isEnabled` branch
     (we just left Auto) releases `grayscaleFromSchedule`. The ONE exception is a slider-drag
     handoff: dragging a slider in Auto calls `retainGrayscaleAsManual()` (clears
     `grayscaleFromSchedule` without touching the system) BEFORE switching to Manual, so
     that path keeps grayscale; clicking Manual/Off explicitly does not, so it's released.
     (NOTE: the earlier "Off clears ALL grayscale" rule was REVERSED by #17 — a hand-toggled
     grayscale now survives Off. Only the SCHEDULE's grayscale is released on leaving Auto.)
- **Invariant:** leaving Auto reverts Auto's grayscale (it was auto-owned); a slider-drag
  handoff is the only way it carries into Manual (via `retainGrayscaleAsManual`). A
  hand-toggled grayscale is a peer, untouched by mode changes (see #17). Grayscale toggles
  from the popover route through `setManualGrayscale` / `retainGrayscaleAsManual`; the
  switch reads `prefs.grayscaleOn` intent (#13/#15).
- **Re-check:** Auto in the grayscale phase → click **Manual** → grayscale OFF (warmth/dim
  carried, no jump). Auto in the grayscale phase → **drag the Dim slider** → forks to
  Manual, grayscale STAYS on. Verified 2026-07-10 via the injected recording-grayscale
  double driving the real preferencesChanged path (A slider-fork keeps, B explicit Manual
  releases, C Auto→Off releases the schedule's grayscale — all pass).

## 17. Grayscale is an always-available independent tool (Phase 3, supersedes #16's Off-clear)
- **Decision (Neeraj, 2026-07-10):** grayscale should be usable in ANY mode, including Off.
  Rationale is scientific: grayscale is a *behavioral* intervention (less colour → less
  dopamine/reward salience → less compulsive scrolling; the ~40 min/day phone-use finding,
  emerging evidence) — a DIFFERENT pathway from warmth/dim's *physiological* melatonin
  effect, and NOT time-locked. So it shouldn't be gated behind "the evening wind-down is on".
- **Change:** the grayscale switch is always enabled (even in Off). The old "Off clears any
  grayscale" branch in `preferencesChanged` was REMOVED — a hand-toggled grayscale now
  survives every mode change (Off included) and is cleared only by its own toggle or app
  quit (`shutdown`). Only the SCHEDULE's grayscale is still released, on leaving Auto (#16).
- **Invariant:** grayscale availability is independent of mode; warmth/dim remain gated to
  Manual/Auto (inert in Off). A hand-toggled grayscale is NEVER swept by a mode change.
  Entering Auto lets the schedule assert its grayscale (daytime → off) — that's Auto taking
  ownership, not a mode-sweep. On quit, grayscale is turned off (don't strand the user with
  a system setting they can't easily undo).
- **Re-check:** Off → the Grayscale switch is enabled; toggle it on → screen desaturates and
  STAYS gray across Off/Manual switches; only its own toggle (or quitting DuskMode) clears it.
  Verified 2026-07-10 (recording double: D2 hand grayscale survives Off, D3 survives
  Off→Manual — pass).

## 18. App whitelist pause — drops warmth+grayscale, KEEPS dim; one shared grayscale suppressor (Phase 3)
- **What it is:** apps in `PreferencesStore.whitelistedApps` pause DuskMode while frontmost
  (popover: "Pause for [app]" switch + paused-apps pull-down; list defaults to EMPTY —
  every escape hatch is deliberately chosen). Watched via
  `NSWorkspace.didActivateApplicationNotification` → `noteFrontmostApp` →
  `updateAppPauseState` → the same `applyEffectiveState` choke point (#12).
- **Invariant — the pause keeps the DIM:** while paused, warmth → 0 (true hue) and
  grayscale is suspended, but dim stays (`applyFilters(enabled:…, warmth: 0, dim: <mode's
  dim>)`). Dimming scales all channels equally (no hue shift) and is the melatonin-critical
  layer (brightness > colour — Nagare 2019/Cajochen 2022), so the whitelist grants colour
  accuracy WITHOUT becoming a full escape hatch. Full brightness = Emergency Color's job.
  Never "upgrade" the pause to drop dim too. Also: constant luminance on ⌘Tab in/out of a
  paused app means no brightness flash (#9 stays safe).
- **Invariant — ONE grayscale suppression mechanism:** Emergency Color and the app pause
  share a single suppressor set (`grayscaleSuppressors` + `grayscaleIntentBeforeSuppression`):
  the FIRST suppressor records + drops grayscale, the LAST to leave restores it
  (unconditionally, never gated on the laggy UA read-back — #12). Never give a new
  "temporarily hold grayscale off" feature its own save/restore pair — two independent
  pairs collide (unpausing mid-emergency must NOT re-enable grayscale while the emergency
  still holds it off, and vice versa). `setManualGrayscale` during a suppression records
  intent only (no system toggle) and the restore honours it.
- **Invariant — the pause suspends, never sweeps:** grayscale ownership
  (`grayscaleFromSchedule`) is untouched by pause/unpause. The schedule's grayscale
  edge-trigger is frozen while paused (paused Auto branch skips `applyScheduleTarget`);
  the first apply after unpausing reconciles any phase boundary crossed. Leaving Auto
  while paused clears the suppressed schedule-grayscale's saved intent (so Auto's
  grayscale doesn't resurrect on unpause — #16's release still holds).
- **Invariant — observation only:** the frontmost-app observer must never reorder windows
  (#1). The pause state flows exclusively through `applyEffectiveState`.
- **Re-check:** manual mode, warmth+dim up, grayscale on → whitelist the frontmost app →
  hue goes neutral AND screen stays dimmed AND grayscale drops; switch away → all three
  return. Fire + cancel Emergency while paused → grayscale stays off until switch-away.
  Verified 2026-07-11 via injected recording-grayscale double + real gamma readbacks
  driving the real paths (30 checks: dim kept at exactly 0.724 while channels equalise,
  both emergency×pause orderings, off-mode pause, intent-change mid-pause, list-removal
  unpause — all pass).

## 19. Popover syncFromState before the view ever loaded → crash (latent since the mode UI)
- **Symptom:** pressing ⌥⌘C (Emergency Color) after launch WITHOUT ever having opened the
  popover crashed the app: `emergencyStateChanged` → `syncFromState` touches implicitly-
  unwrapped views (`stack`, `bedtimeRow`) that don't exist until `loadView` runs.
  Latent since the Off/Manual/Auto redesign added `updateAutoRows` (2026-07-10); caught
  2026-07-11 by the whitelist harness (its `updatePauseRow` tripped the same nil).
- **Fix:** `syncFromState` starts with `guard isViewLoaded else { return }` — nothing to
  sync before the first open; `viewWillAppear` syncs then.
- **Invariant:** any notification-driven UI refresh in the popover must be a no-op until
  the view is loaded. Don't remove the guard; don't add new observers that touch subviews
  without it.
- **Re-check:** fresh launch → ⌥⌘C immediately (popover never opened) → no crash, override
  runs; open the popover during the countdown → button shows the countdown.

## 20. Continuous timeline + opinionated Auto (no sliders) — settled design (2026-07-11)
- **Decision (Neeraj, 2026-07-11, after a full five-lens discussion):** five changes in one
  pass, all approved explicitly:
  1. **The evening is one CONTINUOUS slide, no plateaus.** `CircadianTimeline` interpolates
     warmth/dim linearly from each anchor straight to the next (values are reached exactly
     AT the research-anchored times; between anchors the screen is slightly *ahead*, never
     behind). Rationale: a perceptible step/plateau is a "moment of decision" where users
     fight the app; a ~10 K-per-tick drift is below perception. Do NOT reintroduce
     ramp-then-hold plateaus.
  2. **Sunset anchor dim = 0%** — dusk is colour-only; dimming layers in from the Warm
     anchor (the ≤10 lux science is about the final 1–2 h; a dimmed screen in a still-bright
     room reads as "broken display"). Layering is warmth → +dim → +grayscale by design.
  3. **Grayscale edge at bedtime − 1.5 h** (was −2 h; Neeraj's real-use call), DECOUPLED
     from the colour anchors (`grayscaleStart`, clamped inside the window). The B−2 h
     colour anchor was renamed "Grayscale" → "Dusk".
  4. **Sliders exist ONLY in Manual** (extended 2026-07-12 to drop them from Off too —
     disabled-and-dimmed controls are dead weight; `updateModeRows` inserts the block only
     in Manual). In Auto the status line carries the live values ("Sunset · 5000 K ·
     10% dim · Warm at 8:30 PM"); in Off the popover shows just mode + durable settings.
     **The popover layout principle (settled with Neeraj 2026-07-12):** controls that
     drive the screen right now appear only in the mode where they work (sliders);
     momentary ACTIONS gate on applicability (Emergency Color disabled when nothing is
     filtered); durable SETTINGS stay available in every mode (bedtime, grayscale, the
     pause-for-app list — pausing an app with nothing filtering is valid pre-configuration
     for tonight). Nothing is ever shown disabled-and-dimmed. Also: the daytime Auto
     status shows only "Daytime — starts at sunset, HH:MM" (no zero values — Auto is
     doing nothing, and zeros would read as broken).
  5. **No IP geolocation, no start-time setting** — CoreLocation + timezone fallback stays;
     the app keeps making ZERO network requests (trust story); `min(sunset, bedtime−3h)`
     stays the smart start. A global "intensity" preference is the Phase-4 answer to
     "tonight feels too strong", NOT per-slider access in Auto.
- **Consequence — the slider-fork path is GONE:** with no sliders in Auto there is no
  slider-drag handoff; `retainGrayscaleAsManual()` and `forkToManualIfAuto()` were removed.
  The ONLY Auto → Manual path is the explicit mode click, which adopts the schedule's
  current warmth/dim (no visual jump) and RELEASES the schedule's grayscale (#16's rule,
  now unconditional; #15's handoff exception is moot — grayscale intent switch display
  #13/#15 and hand-toggled-peer rules #14/#17 are unchanged).
- **Invariant:** timeline anchors stay strictly ordered (≥5 min apart) on squeezed
  evenings; `grayscaleStart` stays inside the active window; warmth/dim are monotonically
  non-decreasing across the whole evening (self-tested). The grayscale edge stays
  edge-triggered in AppDelegate (#4) — the timeline changing shape must not add per-tick
  toggles.
- **Re-check:** `swift run DuskModeSelfTest` (continuous-slide, monotonicity, −1.5 h edge,
  Dusk rename, squeezed/late-sunset clamps). Popover: Auto shows bedtime + status only
  (no sliders, no dead space); Off/Manual show sliders; Auto→Manual carries current look.

## 21. Popover never shrank on an in-popover mode switch (dead space) — measure the STACK
- **Symptom:** with the popover OPEN, switching to a mode with less content (e.g. → Auto,
  which drops the 5-view slider block for 2 smaller rows) left ~65 px of dead space at the
  bottom. Reopening fixed it. Caught 2026-07-12 by the mode-switch harness (heights read
  452/452/452 across Off/Manual/Auto when the true Auto content height was 387).
- **Root cause:** `syncFromState` set `preferredContentSize = view.fittingSize` — but while
  the popover is shown, the ROOT view carries autoresizing constraints pinning it to its
  current frame, so `view.fittingSize` just echoes the old size. It can only ever grow via
  content pressure, never shrink. (The 2026-07-10 dead-space fix added
  `layoutSubtreeIfNeeded`, which was necessary but not sufficient.)
- **Fix:** measure the STACK, which uses pure Auto Layout
  (`preferredContentSize = stack.fittingSize`, also in `loadView`). Verified live:
  Off/Manual 452 ↔ Auto 387, popover resizes both directions with no dead space.
- **Invariant:** popover sizing reads `stack.fittingSize`, never the root view's. Any new
  insert/remove of rows must re-run the `layoutSubtreeIfNeeded()` + stack-measure pair in
  `syncFromState`.
- **Re-check:** open popover in Manual → click Auto → popover shrinks flush to the status
  line; click Manual → grows back with all sliders visible.

## 22. App doesn't survive a reboot/shutdown — was never a login item
- **Symptom:** Neeraj reported that after restarting or shutting down his Mac, DuskMode
  is simply gone — no wind-down happens that evening unless he manually relaunches it.
- **Root cause:** the app was never registered with macOS to start at login. Not a
  regression in any engine — a missing piece of first-run setup that was always missing
  (Phase 4's "launch-at-login" line item, just reached earlier because it directly broke
  the app's core promise of unattended nightly automation).
- **Fix:** `Utilities/LaunchAtLogin.swift` wraps the public `SMAppService.mainApp` API
  (macOS 13+, no plist hacks, no private symbols — rule #2). AppDelegate registers ONCE
  on first-ever launch (`PreferencesStore.hasConfiguredLaunchAtLogin` latch). Deliberately
  NO in-app UI (settled 2026-07-16 — see CLAUDE.md): this is a "set once at install"
  setting, not a nightly-use control, and none of Neeraj's other menu bar apps expose it
  either. Opt-out is System Settings → General → Login Items, same as for any other app.
- **Invariant:** launch-at-login state lives ONLY in the OS (`SMAppService`), never
  mirrored into `PreferencesStore` (only the one-time "have we auto-registered yet" latch
  does). Don't add a popover toggle for this — it was tried and deliberately removed;
  don't re-add it without a fresh design conversation.
- **Re-check:** fresh install → `sfltool dumpbtm` shows a DuskMode entry with
  `Disposition: [enabled, …]` after first launch, no UI interaction needed.

---

## 23. Figma/Photoshop tinted anyway — the pause list started empty
- **Symptom:** Neeraj (2026-09-25): "I already have Figma and I don't see that feature
  working." Figma got warmth + grayscale like any other app.
- **Root cause:** not an engine bug. The pause list was deliberately empty by default
  (2026-07-10, intentionality) and only filled from the popover's "Pause for [app]"
  switch. He expected colour-critical apps to be detected on their own; the landing page
  also implied it.
- **Fix (his decision, 2026-09-25):** `DuskModeCore/ColorCriticalApps.swift` holds a
  built-in list of colour-critical bundle IDs (exact, or `*` families for versioned IDs).
  On launch, `Utilities/InstalledApps.swift` scans /Applications and ~/Applications
  (2 levels deep, for Adobe's folders) and adds matches to the normal pause list.
  `noteFrontmostApp` also adds a match the first time it comes to the front. Every
  auto-added ID is remembered in `PreferencesStore.autoPausedApps`.
- **Invariant:** each app is auto-added ONCE EVER. A user who removes Figma with ✕ must
  never see it come back on the next launch (`toAutoAdd` excludes `previouslyAutoAdded`).
  Auto-added apps use the exact same pause path as #18 (hue neutral, dim KEPT,
  grayscale suspended), with no separate code path.
- **Guard:** self-tests "an app removed by the user is never re-added" and family and
  exact matching.
- **Re-check (done 2026-09-25):** fresh build → `defaults read app.duskmode
  whitelistedApps` lists Figma. With Auto at bedtime and Figma in front, gamma reads
  0.264/0.264/0.264 and grayscale is off. Back to Terminal, it reads 0.264/0.137/0.000 and
  grayscale is on.

---

## 24. Released app had no icon — blank placeholder in Finder, Launchpad and About (v1.0)
- **Symptom:** v1.0 installed from the one-liner or the DMG showed macOS's generic
  blank app icon in /Applications, Launchpad, the Gatekeeper prompt and About DuskMode.
  Dev builds looked the same, and nobody noticed because the app only lives in the menu bar.
- **Root cause:** `build.sh` wrote Info.plist and copied `citations.json` but never
  shipped an `.icns` or set `CFBundleIconFile`.
- **Fix (v1.0.1):** `scripts/make-icon.swift` draws the site logo (`site/assets/favicon.svg`)
  on Apple's 824/1024 icon grid and writes the committed `Resources/AppIcon.icns`.
  `build.sh` copies it and sets `CFBundleIconFile`.
- **Invariant:** every built bundle carries `Contents/Resources/AppIcon.icns` and
  `CFBundleIconFile = AppIcon`, and the icon matches the site logo.
- **Guard:** `build.sh` exits non-zero when `Resources/AppIcon.icns` is missing.
  Before any release, `NSWorkspace.icon(forFile:)` on the built app must return the logo,
  not the placeholder.

---

### Standing verification checklist (run after ANY engine/apply-path change)
1. `swift run DuskModeSelfTest` — all green.
2. `./build.sh release run` — single process, menu bar icon appears, and the app shows the
   sunset logo in Finder (#24).
3. Manual mode: warmth up → warm, blacks black; dim up → darkens.
4. Auto mode: status line correct; ⌘Tab flash check (#1);
   grayscale phase → one bezel only (#4); leaving Auto reverts grayscale (#16).
5. Off → screen fully normal, no grayscale. Quit app → screen returns fully to normal.
6. Whitelist a frontmost app → hue neutral, dim KEPT, grayscale suspended; switch away →
   everything returns (#18).
