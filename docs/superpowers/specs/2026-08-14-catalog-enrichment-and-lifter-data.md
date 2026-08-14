# Catalog Enrichment and Lifter Data — Design

**Date:** 2026-08-14
**Status:** Awaiting review
**Extends:** `2026-08-14-foundation-architecture-design.md`

## Problem

The catalog's *schema* is right; its *content* is thin. Comparing our entry for
barbell bench press against a commercial reference:

| Field | Reference | Ours |
|---|---|---|
| Primary muscles | Chest | `chest` ✅ |
| Secondary muscles | Triceps, Shoulders | **empty** ❌ |
| Equipment | Barbell | `barbell` ✅ |
| Movement | Push | `force: push` ✅ |
| Difficulty | Intermediate | **field does not exist** ❌ |

Measured across all 412 entries:

- `primaryMuscles`, `equipment`, `pattern`, `mechanic`, `category`: **100%**
- `force`: 86%
- `secondaryMuscles`: **15%** — 348 entries have none
- `instructions`: 18%
- difficulty: **0%**, no such field

## Why the secondary-muscle gap matters most

Without secondary muscles, nothing can compute real weekly volume per muscle.

A session of bench press, overhead press, dips, and triceps extensions reads as
four different primary muscles and looks balanced. It is four consecutive
triceps exercises. The same trap exists on the pull side: rows, pulldowns, and
curls all load the biceps.

Plan generation is the consumer of this data and does not exist yet, so fixing
it now costs nothing and prevents building generation against data that cannot
support the balance rules in
`2026-08-14-workout-programming-design.md`.

## Fix: derive, do not hand-author

The same insight that produced 412 entries from declarative rules applies here.
Secondary muscles are overwhelmingly a property of the **movement pattern**, not
of the individual exercise:

- horizontal press → triceps, shoulders
- vertical press → triceps
- horizontal pull → biceps, rear delts
- vertical pull → biceps
- squat → glutes, hamstrings, lower back
- hinge → lower back, glutes, traps
- lunge → glutes, hamstrings

That is a `patternSecondaryMuscles` table in `derivation-rules.json`, mirroring
the existing `patternMuscles`. It covers all 412 at once, stays reviewable as a
diff, and honors data-over-code.

Precedence is unchanged and already correct: rules first, then free-exercise-db
enrichment for the 76 matched entries, then hand-authored overrides. Enrichment
data — which is exercise-specific and better — continues to win over the
pattern default.

**Existing invariant still applies:** a muscle may not appear in both primary and
secondary. The generator already re-deduplicates after overrides, and
`musclesDoNotOverlap` enforces it.

## Fix: add difficulty

New field `difficulty` on `Exercise`, an extensible taxonomy like the others,
with `beginner` / `intermediate` / `advanced`.

Derived from what we already know:

- Olympic pattern, or category `olympic weightlifting` → advanced
- compound + barbell → intermediate
- compound + bodyweight/dumbbell/kettlebell → intermediate
- isolation, or equipment machine/cable/band → beginner

free-exercise-db carries a `level` field we never imported; where an entry is
enriched, that value wins over the derived one.

Difficulty lets generation match exercise selection to the lifter's stated
experience rather than ignoring it, and gives the chat something concrete to
reason about when someone says a movement feels too advanced.

## The lifter side — a larger gap than the catalog

Per-exercise data is not what is most missing. `UserProfile` records display
unit, experience, equipment access, goal, and free-text constraints. It does not
record:

**Bodyweight.** Needed to prescribe loads for bodyweight-relative movements and
to make estimated 1RM meaningful as a ratio.

**Current strength.** Nothing captures what the lifter can already lift. The
consequence is concrete: **a first plan cannot suggest any starting weight.** It
can prescribe sets and reps and nothing else. Every load has to be discovered by
trial, and `ProgressionEngine` has no baseline to progress from until a full
session has been logged.

**Structured constraints.** Injuries live as free text. A model can read
"my left shoulder hurts overhead" but nothing can *filter* the catalog by it.
A structured avoid-list — muscle groups, movement patterns, or specific
exercise IDs — makes the constraint enforceable rather than advisory.

### Proposed additions

| Model | Field | Why |
|---|---|---|
| `UserProfile` | `bodyweight: Mass?` | Load prescription and 1RM ratios. |
| `BodyMetric` (new) | `date`, `bodyweight: Mass` | Bodyweight over time, so it is a tracked series rather than one mutable number. Charts and trends need the series. |
| `StrengthBaseline` (new) | `exerciseID`, `load: Mass`, `reps: Int`, `recordedAt` | What the lifter can currently do for a handful of key lifts. Seeds the first plan's loads. |
| `UserProfile` | `avoidedPatterns: [MovementPattern]`, `avoidedExercises: [ExerciseID]` | Enforceable constraints. Free-text `constraints` stays for nuance the model reads. |

All CloudKit-compatible: optional or defaulted, no unique attributes,
relationships optional with inverses.

**The chat collects these conversationally** — it is a natural fit for the shell
in `2026-08-14-app-structure-revision.md`. "What are you benching these days?"
is a better question than a form field, and a lifter who does not know can skip
it and let the first session establish the baseline.

## Verification

Extends `CatalogIntegrityTests`:

- Every non-cardio, non-stretch entry has at least one secondary muscle, or is
  explicitly listed as a genuine single-muscle isolation.
- Primary and secondary never overlap. Already enforced; must keep passing.
- Every entry has a difficulty, and every difficulty value is one the taxonomy
  recognizes.
- Spot-check assertions on known exercises: bench press must list triceps and
  shoulders; a pulldown must list biceps.

Plus unit tests for the difficulty derivation and the new lifter models.

## Sequencing

Before plan generation, because generation consumes all of it. Catalog
enrichment first — it is pure data work with no schema migration. The lifter
models are a schema change and can follow immediately after.

## Out of scope

Instructions coverage stays at 18%. Instructions are for the human reading an
exercise, not for generation, and hand-authoring 337 of them is not worth it
now. Revisit if the UI surfaces them prominently.
