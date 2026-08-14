# App Structure Revision — Plan Blocks and a Chat Shell

**Date:** 2026-08-14
**Status:** Approved
**Revises:** `2026-08-14-foundation-architecture-design.md` (store models)
**Supersedes:** `2026-08-14-modern-minimal-design-system.md` (visual direction)

## What changed and why

Two corrections, both from the user, both caught before the store plan executed.

**1. There was no week layer.** The prior model was
`WorkoutPlan → WorkoutSession(day) → PlannedExercise → LoggedSet`, where a
"plan" *was* a single week and regenerating produced a new one. That cannot
express periodization: no deload week, no planned volume ramp, no training
block. Since progressive overload is the app's entire thesis, a model that
cannot represent a block across weeks is the wrong shape.

**2. The interface is a chat shell, not a tab app.** Plans behave like
projects: each is a persistent, individually addressable container with its own
conversation. You converse to create and revise a plan rather than filling in a
form.

## The hierarchy

Five levels, plus the catalog sitting outside as reference data.

```
ExerciseCatalog (412 entries, bundled, read-only)   ← referenced by ExerciseID
        ▲
        │ exerciseID
        │
TrainingPlan   — a block: goal, start date, week count, status
  └── TrainingWeek   — ordinal within the plan; may be a deload
        └── WorkoutDay   — weekday, focus
              └── PlannedExercise   — catalog ID + prescription
                    └── LoggedSet   — what actually happened
```

`TrainingPlan` also owns a `PlanMessage` thread — the conversation scoped to
that plan, which is what makes it project-like rather than a bare record.

**The catalog is deliberately outside the tree.** It ships with the app and is
never written at runtime; user records reference it by `ExerciseID`. Nothing in
this revision changes that, and nothing about the restructure disturbs the
resolver work that guards it.

## Decisions

**Weeks differ from one another.** Each `TrainingWeek` is stored concretely and
may prescribe different volume, intensity, or exercises than its neighbours.
This costs storage and makes generation harder, and it is the only version
where the week layer earns its place — a template that merely repeats would
make week 12 identical to week 1.

**Plans are fixed-length blocks**, typically 8–12 weeks, with a defined start
and end. This matches how strength programs actually work, gives the chat a
natural moment to review and propose the next block, and makes a plan a
finished thing rather than an endless list.

**Sticky exercise selection still holds**, and matters more now. Within a plan,
a movement slot keeps its exercise across weeks so progression stays
measurable. Week-to-week variation lives in sets, reps, and load — not in
swapping the lift. See `2026-08-14-workout-programming-design.md`.

## The interface

**Chat is the shell and the authoring surface.** Creating a plan, revising it,
reviewing history, and changing settings are all conversational. Plans are
browsable like projects, and opening one scopes the conversation to it.

**One screen is deliberately not chat: the active workout.** Logging sets at
the gym is the app's most-used surface and is inherently direct manipulation —
the spreadsheet grid, tap-to-complete, the rest timer. Nobody types "I did 185
for 5" between sets while out of breath. That screen stays a logbook.

This is the single exception. Everything else is conversational.

**Visual direction: the Claude interface.** This replaces the modern-minimal
direction, and is a more concrete target — generous whitespace, a warm neutral
ground rather than stark white, restrained type, content-forward layout with
chrome kept quiet, and messages as the primary structure.

The skin-is-not-a-mechanic rule carries forward unchanged from the superseded
specs: no points, streaks, badges, levels, or celebratory UI. Estimated 1RM
stays a plain data point.

## Store models

Replaces the store-model list in the foundation architecture spec.

| Model | Holds |
|---|---|
| `UserProfile` | Display unit, experience, equipment access, constraints, goal. |
| `TrainingPlan` | Title, goal, start date, week count, status. Owns weeks and messages. |
| `TrainingWeek` | Ordinal within the plan, a label such as "Accumulation" or "Deload", `isDeload`. Owns days. |
| `WorkoutDay` | Weekday, focus, duration, completion. Owns planned exercises. |
| `PlannedExercise` | `exerciseID` plus a denormalized display name, order, target sets, rep range, suggested load, rest, tempo, notes. Owns logged sets. |
| `LoggedSet` | Load as a `Mass` (nil for bodyweight), reps, RPE, completion, warmup flag. |
| `PlanMessage` | One conversational turn scoped to a plan: role, text, timestamp. |

`TrainingSchedule` is absorbed: training days and session duration are
properties of a plan, since different blocks may train different days. What
remains standing is `UserProfile`.

Every model is written to CloudKit's constraints — properties optional or
defaulted, no unique attributes, relationships optional with inverses.

## Consequences for work already planned

- **`2026-08-14-store-layer-and-cleanup.md`** — Task 4 is rewritten for the new
  hierarchy. `TrainingSchedule` is dropped; `TrainingPlan`, `TrainingWeek`, and
  `PlanMessage` are added; `WorkoutSession` becomes `WorkoutDay`.
- **`2026-08-14-modern-minimal-design-system.md`** — superseded by the Claude
  visual direction above.
- **The conversational onboarding project is absorbed into the shell.** Chat is
  no longer a first-run screen that hands off to a tab app; it is the app. The
  recorded decisions about scripted-spine-plus-model-extras and graceful
  degradation without Apple Intelligence still apply to how the chat behaves.
- **Nothing in `Domain/` or `Catalog/` changes.** The catalog, the resolver,
  `Mass`, and the taxonomies are unaffected — which is the payoff for having
  built them as a layer with no upward dependencies.
