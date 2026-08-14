# Retro 8-Bit Theme — Design

**Date:** 2026-08-14
**Status:** Approved for planning
**Scope:** App-wide visual restyle of LiftingPlan. Views and a new theme layer only.

## Problem

LiftingPlan works, but it looks like stock SwiftUI — system `Form`s, default
pickers, native list rows. It reads as a generic utility rather than something
with a point of view.

We want an 80s arcade / retro 8-bit visual identity across the whole app.

## Governing principle: the retro is a skin, not a mechanic

This is a training tool that happens to look like an arcade cabinet. It is not a
game and we are not gamifying training.

**Explicitly out of scope, permanently:**

- Points, scores, or "high score" framing
- Streaks, badges, achievements, levels, XP
- Celebratory flashes, confetti, or fanfare on hitting a number

Scores invite optimizing for the score. In lifting that means ego-lifting and
chasing a number instead of following the program — the opposite of what the
`ProgressionEngine` is for.

Estimated 1RM stays exactly what it is today: a data point on a trend chart with
a plain label. The term "PR" is acceptable because it is ordinary
strength-training vocabulary, not a game term.

Where the retro style and the useful choice diverge, the useful choice wins.

## Design tokens

### Color

Six core tokens. Named once in `RetroPalette`, never hardcoded at call sites.

| Token | Hex | Role |
|---|---|---|
| `crtBlack` | `#0B0D14` | App background. A powered-on CRT, not pure black. |
| `cabinetSteel` | `#1C2233` | Panel and card fill. |
| `marqueeMagenta` | `#FF2E6E` | Primary accent — buttons, active tab. |
| `screenCyan` | `#2BE0DC` | Secondary — rest timer, in-progress states. |
| `plateAmber` | `#FFC531` | Highlighting a personal best as data. No celebration UI. |
| `powerGreen` | `#45E06A` | Completed set. |

**Plate-color load coding.** Load chips use the standard Olympic bumper-plate
colors — red `#E4342B`, blue `#2C6BE4`, yellow `#FFC531`, green `#45E06A`,
white `#F2F2F2`. Heavier sets read redder. This is functional, not decorative:
lifters already recognize these colors from real plates.

The plate *coding scheme* is used on load chips and nowhere else, so the
mapping from color to weight retains its meaning. Two of its hex values are
deliberately shared with the core tokens above (`#FFC531`, `#45E06A`) to keep
the overall palette tight.

### Typography

Three roles, all accessed through `RetroFont` helpers.

- **Display** — `Press Start 2P`. Headings, buttons, day labels, numerals.
  Always uppercase, always at small sizes: it is a wide face that consumes
  horizontal space quickly.
- **Body** — SF Pro Rounded. Coaching cues, goal text, chat bubbles. Soft and
  chunky reads more 80s-arcade than a neutral grotesque while staying readable
  at paragraph length.
- **Data** — SF Mono. The set-logging table, so `LBS` / `REPS` columns align and
  the grid reads as a clean readout.

Press Start 2P ships in the app bundle. It is licensed under the SIL Open Font
License, which permits commercial bundling. The license file ships alongside it
and the font is registered via a `UIAppFonts` entry in `Info.plist`.

### Layout

- An 8-point spacing grid.
- Hard 3px borders, zero corner radius.
- Offset shadows with no blur — 8-bit graphics have no antialiasing.
- Panel bevel: light top-left edge, dark bottom-right.
- A scanline overlay across the app at ~4% opacity. Present if you look for it,
  invisible if you do not.

### Motion

Stepped, not eased. Timers tick in discrete once-per-second frames; state
changes hard-cut like sprite swaps. Reduced-motion disables scanlines and any
stepped flashing.

## Signature element: the rest timer

The rest timer is the one moment where you are three feet from the phone,
mid-set, slightly out of breath. It becomes a full-bleed pixel countdown in
`screenCyan` with enormous digits, hard-stepped once per second, readable at
arm's length across a gym floor.

This is where the retro choice and the useful choice coincide: chunky
high-contrast pixel digits genuinely outperform small anti-aliased text when
you are squinting between sets. Boldness is spent here; everything around it
stays quiet.

## Code structure

A single `Theme/` folder holds the token layer.

| Component | Responsibility |
|---|---|
| `RetroPalette` | The six color tokens as `Color` extensions, defined once. |
| `RetroFont` | `.display(size:)`, `.body(size:)`, `.data(size:)` helpers. Changing a typeface is a one-line edit. |
| `RetroPanel` | The beveled container as a `ViewModifier`: 3px border, zero radius, bevel edges, hard offset shadow. |
| `RetroButton` | A `ButtonStyle` whose pressed state shifts 2px inward, the way a physical arcade button seats. |
| `ScanlineOverlay` | Applied once at the app root. Honors `accessibilityReduceMotion` and `accessibilityReduceTransparency`. |

Views compose these rather than styling themselves. This keeps the rollout
mechanical instead of a per-screen rewrite, and means a token change propagates
everywhere.

## Rollout order

1. `Theme/` foundation, font bundling, app root background and scanlines.
2. `ActiveWorkoutView`, `SetRowView`, `RestTimerBar`, `TimerRing` — highest
   traffic, and where the signature lives.
3. `PlanOverviewView`, `SessionDetailView`.
4. `HistoryView`, including rebinding Swift Charts colors to the palette.
5. `SettingsView`, `SetupView`.
6. `WeekdayChips` and remaining components.

## Risks

**SwiftUI `Form` and `List` resist custom styling.** Hard 3px borders and zero
corner radius cannot be applied to them cleanly. `SettingsView` and `SetupView`
must be rebuilt as custom `ScrollView` layouts composed from `RetroPanel`. This
is the largest chunk of the work and the easiest to underestimate.

**Press Start 2P at fixed sizes would break Dynamic Type.** Display text uses
relative scaling rather than pinned point sizes.

**Contrast.** A dark palette with saturated accents can fail legibility for body
text. Mitigated by the contrast test below.

## Accessibility floor

- Dynamic Type works throughout; no pinned font sizes.
- Body-text-on-background pairs meet WCAG AA.
- Reduced motion disables scanlines and decorative stepped flashing. It must not
  stop the rest-timer countdown, which is functional information — the digits
  keep updating, they simply stop flashing.
- Reduced transparency disables the scanline overlay.
- VoiceOver labels are unchanged by this work.

## Testing

The existing Swift Testing suites cover pure logic (`ProgressionEngine`,
`TemplatePlanBuilder`, blueprint mapping, rest-timer math) and are unaffected —
this project changes no models or services.

Theme work is visual, so verification is primarily build, run, and screenshot
each screen on both simulator and device.

One piece is genuinely unit-testable and worth locking down: `RetroPaletteTests`
asserts that each text-on-background token pair meets the WCAG AA contrast
ratio, so an unreadable color combination cannot be introduced later.

## Out of scope

- No changes to `Models/` or `Services/`.
- No new features. This is a restyle.
- The conversational onboarding chat is a separate project (below).

## Next project: conversational onboarding

Decided during this brainstorm and recorded here so the next spec cycle starts
from these, rather than rediscovering them.

- **Replaces** the first-run form with a chat that asks the five core questions
  and then a small number of adaptive follow-ups before generating.
- **Approach:** scripted spine plus model-assisted extras. A fixed ordered list
  of steps, each with question text, quick replies, and a parser into
  `TrainingPreferences`. When the on-device model is available it adds 2–3
  adaptive follow-ups and parses free-text answers via guided generation.
- **Fallback:** without Apple Intelligence (including most simulators) the
  scripted chat still runs end to end on quick replies; follow-ups are skipped.
  Everyone gets a chat.
- **Input:** hybrid — quick-reply chips for days, duration, equipment, and
  experience, with the keyboard always available.
- **Editing later:** the form survives for editing preferences from Settings.
  Re-running a conversation to change one field would be tedious.
- **Build order:** after this theme project, so the chat is built themed rather
  than built twice.
