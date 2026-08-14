# Modern Minimal Design System — Design

**Date:** 2026-08-14
**Status:** SUPERSEDED by `2026-08-14-app-structure-revision.md`, which sets the
visual direction to the Claude interface and makes chat the app shell rather
than a first-run screen.

What survives: the skin-is-not-a-mechanic rule (no points, streaks, badges, or
celebratory UI), the token-layer code structure, the accessibility floor and
contrast test, and the observation that SwiftUI `Form`/`List` resist custom
styling. What is dropped: the cobalt/IBM Plex palette and the
finished-work-recedes signature, both of which assumed a tab-based app.
**Supersedes:** `2026-08-14-retro-8bit-theme-design.md`
**Scope:** App-wide visual restyle. `Views/` and a new `Theme/` layer only.

## Problem

LiftingPlan looks like stock SwiftUI — system `Form`s, default pickers, native
list rows. It reads as a generic utility with no point of view.

The direction is modern and minimal, with full adaptive light and dark support.

## Governing principle: the style is a skin, not a mechanic

Carried forward unchanged from the superseded spec, because it survives any art
direction.

This is a training tool. It is not a game and we are not gamifying training.

**Permanently out of scope:** points, scores, streaks, badges, achievements,
levels, XP, celebratory flashes, confetti, fanfare.

Scores invite optimizing for the score. In lifting that means ego-lifting and
chasing a number instead of following the program — the opposite of what
`ProgressionEngine` exists to do. Estimated 1RM stays a plain data point on a
chart. "PR" is acceptable as ordinary strength-training vocabulary.

Where style and usefulness diverge, usefulness wins.

## Avoiding generic minimal

"Minimal" is where design goes to become anonymous, and the current crop of
AI-generated interfaces clusters hard around three looks: warm cream with a
serif display and a terracotta accent; near-black with a single acid-green or
vermilion accent; and broadsheet hairline rules with dense columns.

This design deliberately avoids all three. The point of view instead comes from
what the app actually is: **a logbook and an instrument.** The most
characteristic artifact in a lifter's world is the training log — a dense table
of numbers that means something. So numerals are the hero, and the interface is
mostly the act of reading and entering them.

## Signature: finished work recedes

The single memorable behavior. **Completed sets get quieter, not louder.**

When you check a set off, the row does not light up green or celebrate. It
desaturates, drops in type weight, and steps back to a muted tone. The active
set becomes the only high-contrast element on the screen.

The practical effect is that the screen gets progressively calmer as you work
through a session, and your eye is always pulled to the one thing you are
supposed to do next. It is the exact opposite of confetti, and it follows
directly from the skin-not-a-mechanic principle: progress is shown by removing
emphasis rather than by adding reward.

Boldness is spent here. Everything else stays disciplined.

## Design tokens

### Color

Near-monochrome plus one accent. Every token is defined once in `Palette`, with
a light and a dark value, and resolved through the environment color scheme.

| Token | Light | Dark | Role |
|---|---|---|---|
| `canvas` | `#FAFAF8` | `#101113` | App background. Off-white is faintly warm; the dark is faintly cool. |
| `surface` | `#FFFFFF` | `#1A1C1F` | Raised panels, rows, sheets. |
| `ink` | `#14161A` | `#F2F3F5` | Primary text and numerals. |
| `inkMuted` | `#6B7280` | `#9BA1AA` | Labels, units, secondary data. |
| `hairline` | `#E6E6E2` | `#26292E` | Structural rules only. |
| `accent` | `#2743F0` | `#5B72FF` | The active element. One accent, used sparingly. |

The accent is a deep cobalt — precise and instrument-like, and deliberately not
the acid green or vermilion that the default dark-mode look reaches for. The
dark-mode value is lightened rather than reused, so contrast holds on a dark
canvas.

**There is no success color.** Completion is expressed by recession — muted ink
and lighter weight — not by turning something green. This is the signature
behavior, expressed in the token set.

### Typography

Two roles from one engineered family, so the app reads as a coherent instrument.

- **Text** — IBM Plex Sans. Headings, labels, coaching cues, chat copy.
- **Data** — IBM Plex Mono. Weights, reps, timers, the logging grid. Tabular
  figures mean columns align and digits do not shift width as they change.

Both are SIL Open Font License, so bundling in a commercial app is fine. The
license file ships alongside, and fonts register via `UIAppFonts` in
`Info.plist`.

Plex is chosen over Inter or system SF because it carries an engineered,
measured character that suits a logbook, and because Inter has become the
default choice that makes products look interchangeable.

The type scale is deliberately short — four sizes, two weights. The weight
numeral is the largest type in the app; everything else is quiet around it.

### Layout

- 8-point spacing grid.
- Generous whitespace. Density comes only from the logging grid, where it is
  useful.
- Hairline rules only where they encode structure. No decorative dividers.
- No drop shadows. Elevation is expressed by surface tone against canvas.
- Corner radius is small and consistent — 10pt on panels, 8pt on controls.
- Numerals right-aligned and tabular so columns scan vertically.

### Motion

Restrained and native. Springs for state changes, no bounce for its own sake,
nothing decorative. The recession of a completed set is animated because the
change carries meaning; nothing else animates without a reason.

`accessibilityReduceMotion` collapses animations to instant state changes.

## Code structure

A single `Theme/` folder. Views compose these rather than styling themselves, so
a token change propagates everywhere and the rollout stays mechanical.

| Component | Responsibility |
|---|---|
| `Palette` | Every color token with light and dark values, resolved by color scheme. |
| `Typography` | `.text(...)` and `.data(...)` helpers over Plex Sans and Plex Mono. Changing a typeface is a one-line edit. |
| `Panel` | The standard container: `surface` fill, 10pt radius, hairline border, no shadow. A `ViewModifier`. |
| `PrimaryButton` | `ButtonStyle` in accent, with a pressed state. |
| `SetRowStyle` | Encapsulates the signature: active versus completed emphasis, so recession is defined once rather than reimplemented per view. |

## Rollout order

1. `Theme/` foundation, font bundling, app root background.
2. `ActiveWorkoutView`, `SetRowView`, `RestTimerBar`, `TimerRing` — highest
   traffic, and where the signature lives.
3. `PlanOverviewView`, `SessionDetailView`.
4. `HistoryView`, including rebinding Swift Charts colors to the palette.
5. `SettingsView`, `SetupView`.
6. `WeekdayChips` and remaining components.

## Risks

**SwiftUI `Form` and `List` resist custom styling.** `SettingsView` and
`SetupView` must be rebuilt as custom `ScrollView` layouts composed from
`Panel`. This is the largest chunk of the work and the easiest to underestimate.

**Adaptive theming doubles the verification surface.** Every screen needs
checking in both schemes, and every contrast pair needs testing twice.

**Recession must not read as "disabled."** A completed set is muted, but it has
to stay legible and remain editable — you must be able to correct a logged set.
Muted ink, not disabled ink, and the tap target is unchanged.

## Accessibility floor

- Dynamic Type throughout. No pinned font sizes.
- All text-on-background pairs meet WCAG AA in both light and dark.
- Completed rows meet AA as well; recession reduces emphasis, never legibility.
- Reduced motion collapses animation to instant state changes.
- VoiceOver labels unchanged; completion is announced, not merely shown by tone.

## Testing

Existing Swift Testing suites cover pure logic and are unaffected — this
project changes no models or services.

Visual work is verified by building and screenshotting each screen in both
light and dark on simulator and device.

One part is genuinely unit-testable and worth locking down: `PaletteTests`
asserts every text-on-background token pair meets WCAG AA **in both schemes**,
including the muted ink used for completed rows. This prevents both an
unreadable combination and the recession effect being pushed too far.

## Out of scope

- No changes to `Models/` or `Services/`.
- No new features. This is a restyle.
- The exercise catalog and the conversational onboarding are separate projects.

## Related projects and build order

Three projects total, to be built in this order.

**1. Exercise catalog** (next spec). Today there is no exercise library. A
hardcoded list of 37 names lives inside `TemplatePlanBuilder.swift`, carrying
only a name and a muscle group, and `PlannedExercise.name` is a free-form
`String`. Model-generated plans invent exercise names that are validated against
nothing, so the app can prescribe a movement that exists in no catalog.

This project adds a canonical `Exercise` entity with stable IDs, validates
model output against it, and designs a media slot for future demonstration
animations.

On MoveKit: it sells 3D exercise demonstration clips as MP4, at $4.99 per clip
or $149–$299 per pack. It is not a UI animation framework. No watermarked
evaluation tier was found — their terms mention no trial or sample provision,
though the site references a free sample pack. **Decision: build the catalog and
the media slot now, defer any purchase.** Stable IDs are a hard prerequisite —
a video file cannot be mapped to a free-text string the model invented.

**2. This design system.**

**3. Conversational onboarding.** Decisions already made and recorded so the
spec cycle starts from them:

- Replaces the first-run form with a chat covering the five core questions plus
  a small number of adaptive follow-ups before generating.
- Scripted spine plus model-assisted extras: a fixed ordered list of steps, each
  with question text, quick replies, and a parser into `TrainingPreferences`.
  When the on-device model is available it adds 2–3 adaptive follow-ups and
  parses free-text answers via guided generation.
- Without Apple Intelligence (including most simulators) the scripted chat runs
  end to end on quick replies and follow-ups are skipped. Everyone gets a chat.
- Hybrid input: quick-reply chips for days, duration, equipment, and experience,
  with the keyboard always available.
- The form survives for editing preferences from Settings.
- Built after the design system, so the chat screen is not built twice.
