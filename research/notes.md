# NightFlow — Research Notes (Phase 0)

These are the implementation-relevant numbers pulled from the studies in `citations.json`.
When a later phase asks "what value should this preset be?", the answer comes from here.

---

## The core scientific picture

Three independent mechanisms delay sleep, and each needs its own layer:

1. **Spectral (color) suppression of melatonin** — driven mainly by melanopsin, peaking at **~460-480nm (blue)**, with a large **early contribution from ~555nm (green)** via cones. → *Color layer (overlay tint + optional gamma).*
2. **Intensity (brightness) suppression + alerting** — melatonin is suppressed at very low lux; brightness independently raises alertness/cortisol. → *Dimming overlay layer.*
3. **Behavioral reward (compulsion)** — color makes screens more rewarding; grayscale interrupts the loop. → *Grayscale layer.*

An app that only warms color (Night Shift, basic f.lux) addresses ~1/3 of the problem. NightFlow's pitch is stacking all three on an automated timeline.

---

## Numbers that set the presets

### Color targets (per `citations.json` blue-light + green-light + red-light)
- Peak melatonin suppression: **459-484nm**, single worst point ~**464-480nm**. Cut this band hardest.
- **Green (~555nm) matters early** and fades over hours → cut green aggressively in the first 1-2h of wind-down; it matters less deep into the night.
- Melatonin suppression falls off sharply **above ~600nm**; **620-670nm red is the safe tail**. Red Mode targets this.
- Practical preset ladder (color temperature is the user-facing proxy; the engine also independently attenuates the green channel):

  | Preset   | Color Temp | Extra Green Cut | Science anchor |
  |----------|-----------|-----------------|----------------|
  | Sunset   | ~5000K    | ~10%            | Early wind-down, gentle |
  | Warm     | ~3400K    | ~25%            | Blue + early-green reduction |
  | Bedtime  | ~2700K    | ~50%            | Heavy blue+green cut |
  | Red Mode | ~1900K    | ~85%            | Push toward 620-670nm safe tail |

### Brightness targets (per `citations.json` brightness) — UPDATED with 2019-2022 research
- **~6 lux → ~50% melatonin suppression** in sensitive individuals (Zeitzer 2000). Even a dim screen is not "safe" by color alone.
- **Brightness matters MORE than color (Nagare/LRC 2019).** Warming color alone (the Night Shift / basic-f.lux approach) did NOT meaningfully reduce melatonin suppression unless brightness was also lowered. → **The dimming overlay is our highest-leverage layer, not a nice-to-have.** This is also our sharpest differentiator vs color-only apps.
- **Modern quantitative target (Brown et al. 2022, PLOS Biology consensus, using melanopic EDI / CIE S 026):**
  - Evening wind-down: **≤10 lux melanopic EDI**
  - Sleep environment: **≤1 lux melanopic EDI**
  - (Daytime for contrast: ≥250 lux — future "morning boost" feature could use this.)
  - We can't measure melanopic EDI directly from software, but these anchor the *direction*: deep phases should push the screen toward "barely-lit," not just "warm."
- Hardware min brightness is not low enough → software overlay must go further. Spec allows 0-95% overlay opacity.
- Each timeline phase pairs a color target with a dimming step (defaults, all user-adjustable):
  - Sunset: -10% · Warm: -20% · Grayscale phase: -30% · Red: -50% · Bedtime: max (toward the ≤1 lux goal).

### Timing (per `citations.json` timing)
- **DLMO ≈ 2-3h before natural sleep onset.** Light in this window is what delays the clock.
- Therefore: **wind-down begins ~2-3h before target bedtime.** Deepest filtering + grayscale in the final **1-2h**.
- Varies by chronotype → timeline must be user-adjustable, not fixed. Anchor to user's target bedtime, with sunset as the earliest trigger.

### Grayscale (per `citations.json` grayscale)
- Grayscale cut phone use by **~40 min/day** (Holte & Ferraro 2020), replicated 2024.
- Mechanism is **reward/compulsion**, not light → schedule it for the doomscrolling window (Phase 3, ~2h before bed), independent of color.
- Evidence is **"emerging"** — the app's Science tab must label it honestly and not imply it's as settled as the light research.

---

## Honesty rules for the in-app Science tab
- Show the `effectStrength` label for each topic (strong / moderate / emerging).
- Blue light & timing & brightness = strong. Green = moderate (note the decay-over-time nuance). Red = moderate. Grayscale = emerging.
- Never imply grayscale has the same evidence weight as blue-light suppression. Overselling weak evidence is the exact failure mode that would kill credibility.
- **Include the `limitations` topic (counter-evidence) prominently.** The 2023 Cochrane review found blue-light *filtering glasses* don't clearly help. Our defense/positioning: those glasses block only a weak slice of blue and don't dim — NightFlow reduces the actual melanopic *dose* (dimming + heavy spectral shift + correct timing), which is what the stronger evidence (Brown 2022, Nagare 2019, Cajochen 2022) supports. Say this openly; it builds trust and is factually our edge.

## Recency check (done 2026-07-06)
Verified the 2020-2026 literature, not just the foundational papers. Key modern additions:
- **Brown et al. 2022 (PLOS Biology)** — consensus melanopic-EDI targets (≤10 evening / ≤1 sleep). Now our quantitative brightness anchor.
- **Nagare/LRC 2019** + **Cajochen 2022 meta-analysis** — brightness > color; validates dimming-first design.
- **Cochrane 2023 + Frontiers 2025** — blue-blocking *glasses* underwhelm; folded in as honest counter-evidence and positioning.
The foundational action-spectrum studies (Brainard/Thapan 2001, Gooley 2010, Zeitzer 2000) remain valid and are still the gold standard for the *spectral* numbers — recent work refines the metrics and dosing, it doesn't overturn them.

---

## How the science maps to architecture (decided with the user)
- **Foundation = overlay `NSWindow`** (transparent, click-through, red/amber/black tint + variable alpha). Handles color layer 1 AND dimming layer 3. Chosen because it's the most upgrade-proof macOS technique (unchanged ~20 years) and sidesteps the gamma-table regression on newest Apple Silicon (macOS Tahoe 26.3/26.4 broke `CGSetDisplayTransferByTable` display application on M5-class hardware — see session notes in CLAUDE.md).
- **Gamma tables = optional quality enhancer**, behind a protocol, degrades silently to overlay-only if it fails.
- **Grayscale layer 2 = toggle Apple's built-in System Color Filters** (Accessibility → Display → Color Filters → Grayscale). We do NOT reimplement it and we avoid the private `UAGrayscaleSetEnabled` API per the user's "no fragile OS internals" requirement. Open question for Phase 3: cleanest public way to drive the system toggle on schedule vs. deep-linking the user to the ⌥⌘F5 shortcut. To be resolved with a spike before building Phase 3.

---

## Open technical questions to resolve before their phase
- **Phase 1 spike:** confirm click-through tinted overlay covers all screens, follows Spaces, survives sleep/wake, is click-through, and reads <1% CPU idle.
- **Phase 2:** pick a solar-position algorithm (NOAA solar calc is public-domain and accurate enough; implement ourselves per user's "code everything ourselves" preference — no dependency).
- **Phase 3:** the grayscale automation method (public toggle vs. guided shortcut). This is the one remaining unknown; everything else is settled.
