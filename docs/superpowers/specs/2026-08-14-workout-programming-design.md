# Workout Programming — Design

**Date:** 2026-08-14
**Status:** Approved direction, implemented in the Store/Services plan
**Scope:** How sessions and weeks are organized. Not visual design, not persistence.

## MoveKit provides none of this

MoveKit sells exercise demonstration clips. Their per-exercise metadata is name,
slug, muscle group, clip duration, a description, and a "loopable" flag, with
browse filters for equipment, muscle, and difficulty. There is no split
structure, no set or rep prescription, no progression model, and no session
ordering.

Programming is ours to build. The catalog from the Domain/Catalog plan already
carries what it needs — crucially `pattern`, plus `mechanic`, `equipment`,
`force`, and `category`.

## Organize by movement pattern, not muscle group

This is the central decision, and it is why `MovementPattern` exists in the
taxonomy.

Muscle-group splits ("chest day", "arm day") are a bodybuilding-magazine
inheritance. They cause three problems for the lifter this app is for: they
train each muscle once a week when twice is better for both strength and
hypertrophy; they make imbalance easy to accumulate unnoticed; and they organize
around anatomy rather than around what a body actually does.

Pattern-based organization instead treats the fundamental human movements as the
unit: **squat, hinge, lunge, horizontal press, vertical press, horizontal pull,
vertical pull, carry.** Every session is assembled from patterns, and the
isolation patterns (curl, extension, raise, fly, shrug, flexion, rotation) fill
the accessory slots.

The practical payoff is that balance becomes checkable in code. A week that
prescribes four horizontal presses and one horizontal pull is detectably wrong.

## Balance constraints

Enforced when a week is assembled, as data-driven rules rather than hardcoded
conditionals:

- **Horizontal pull volume ≥ horizontal press volume.** The single most useful
  rule in the file. Most self-directed lifters press far more than they pull,
  and the shoulder pays for it.
- **Vertical pull volume ≥ vertical press volume.**
- **Every training week includes at least one squat, one hinge, and one pull.**
- **No pattern appears in more than half a session's slots.**

## Session structure

Ordered by neurological demand, heaviest first, because technique degrades as
fatigue accumulates and the most demanding movement deserves the freshest
lifter:

1. **Primary compound** — a squat, hinge, or heavy press/pull. Lowest reps,
   longest rest.
2. **Secondary compound** — a different pattern from the primary.
3. **Accessory work** — isolation patterns, moderate to high reps, short rest.
4. **Optional finisher** — carry, flexion, or rotation.

How many slots is a function of the session's time budget, which the app already
collects. Rest periods, not exercise count, are what actually consume a session.

## Weekly templates by available days

Stored as JSON, one entry per day count, so adding or tuning a split is a data
edit:

| Days | Split | Rationale |
|---|---|---|
| 1 | Full body | Everything must appear or it is never trained. |
| 2 | Full body ×2 | Still better than an upper/lower split at this frequency — each pattern gets touched twice. |
| 3 | Full body ×3, or Push / Pull / Legs | Full body for beginners, PPL once volume tolerance is higher. |
| 4 | Upper / Lower ×2 | Each pattern twice a week, comfortable per-session volume. |
| 5 | Upper / Lower / Push / Pull / Legs | |
| 6 | Push / Pull / Legs ×2 | |

Every template targets **each major pattern at least twice per week**, which is
the frequency the evidence supports and the thing muscle-group splits get wrong.

## Exercise selection is sticky

The most important rule for this app specifically, and the easiest to get wrong.

**Regenerating a plan must not silently swap the exercises.** Progressive
overload is measured per exercise: if this week prescribes a barbell bench press
and next week a dumbbell bench press, there is no comparison to make, the
progression engine has no history to read from, and the lifter cannot tell
whether they are getting stronger.

So plan regeneration adjusts **loads, reps, and sets** against a stable movement
list. The exercise list changes only when:

- the lifter's available equipment changes,
- the lifter explicitly asks to swap a movement, or
- a training day is added or removed, which necessarily changes the split.

When a swap is needed, `ExerciseCatalog.substitutes(for:)` supplies replacements
sharing the movement pattern, so the slot's purpose survives the substitution
and history can still be related.

## What this means for the existing code

`TemplatePlanBuilder` is rewritten against these rules and the catalog. Its
current form — a `switch` over focus strings with exercise names and rest
seconds baked into branches — is exactly what the data-over-code constraint
forbids. Split definitions, slot counts, rep ranges, and rest prescriptions all
become JSON.

The on-device model's role narrows accordingly: it is good at interpreting a
lifter's stated goal and choosing among catalog exercises, and bad at
guaranteeing balance or structural correctness. So the app owns the skeleton —
split, slot count, pattern per slot, balance rules — and the model fills slots
from the catalog. Anything it returns still passes through `ExerciseResolver`.
