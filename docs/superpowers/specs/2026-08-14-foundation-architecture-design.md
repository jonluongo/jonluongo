# Foundation Architecture — Design

**Date:** 2026-08-14
**Status:** Awaiting review
**Scope:** Rebuild the data foundation. Exercise catalog, user data model, layer
boundaries. Views change only where the model forces them to.

## Why this comes first

The app currently rests on two defects that no amount of UI work can paper over.

**Weights have no unit.** `SetLog.weight` is a bare `Double?`. Every logged
weight is pounds by convention only — nothing in the model says so. Introducing
kilograms later would silently reinterpret every set ever logged.

**Exercise identity is a string.** `PlannedExercise.name` is free-form text, and
`PerformanceHistory` matches exercises with `exercise.name.lowercased()`.
Meanwhile `PlanGenerator` lets the on-device model invent exercise names that are
validated against nothing. So "Barbell Bench Press" and "Bench Press (Barbell)"
are two different exercises, history fragments, and progression silently resets.

The app's memory of what you lifted currently rests on string matching. That is
the junk being cleared.

## Decisions taken

- **CloudKit sync from the start.** Models are built to CloudKit's constraints.
- **The catalog matches MoveKit's 412 exercises exactly**, so their animations
  drop in later with no mapping work.
- **Existing on-device data is wiped.** Pre-release app; a clean schema is worth
  more than current test data.

## Exercise identity: the MoveKit slug is the canonical ID

MoveKit publishes 412 exercises at `movekit.com/exercises/<slug>`. All 412 slugs
were retrieved from their public sitemap and form the canonical key set —
`barbell-bench-press`, `zercher-squat`, `arnold-press`, and so on.

Using their slug as our `ExerciseID` means that when a pack is purchased, the
files arrive already named for the IDs we store. Integration becomes dropping
`<slug>.mp4` into the bundle and setting one field. No mapping table, no fuzzy
reconciliation, no migration.

This costs nothing now. We are adopting a naming convention, not a dependency —
if MoveKit is never purchased, these are just stable, readable identifiers.

Note that the 412 include cardio machines and stretches (`assault-bike`,
`abdominals-stretch-variation-one`) as well as lifts. The catalog carries them
all with a `category` field so plan generation can filter to resistance work.

### Catalog metadata

Each entry needs more than a name. Fields: `id` (slug), `displayName`,
`aliases`, `primaryMuscles`, `secondaryMuscles`, `equipment`, `mechanic`
(compound/isolation), `force` (push/pull/static), `category`, `instructions`,
and `mediaAsset` (nil until animations are purchased).

Muscle, equipment, and instruction data is seeded from
[free-exercise-db](https://github.com/yuhonas/free-exercise-db) — public domain,
800+ entries — matched to MoveKit slugs by normalized name, with unmatched
entries filled by hand. The match rate will not be 100%; the gap is hand-authored
and the seeding script is kept so the catalog can be rebuilt reproducibly.

## The catalog is not in the database

This is the central structural decision.

The catalog is **reference data**: it ships with the app, never changes at
runtime, and versions with releases. It is a bundled JSON file loaded into
memory.

User data is **records**: mutable, personal, synced.

Putting 412 immutable exercises into SwiftData would sync a static dataset to
every device through iCloud, and make catalog updates a migration rather than a
file swap. Keeping them separate means user records reference exercises by slug
and the catalog can be regenerated freely.

## Extensibility principles

The foundation has to carry features that do not exist yet. These rules are
binding on implementation, not aspirational.

**Data over code.** Anything that is a fact about training — the exercise
catalog, split templates, rep and rest prescriptions per goal and experience —
lives in versioned JSON, not in Swift control flow. The current
`TemplatePlanBuilder` is the anti-pattern to eliminate: a `switch` over focus
strings with exercise names and rest seconds baked into branches. Adding a new
split or adjusting a prescription must be a data edit reviewable as a diff, with
no logic recompiled.

**Protocol seams at every boundary.** `ExerciseCatalogProviding`,
`PlanGenerating`, `MediaProviding`, `ProgressionStrategy`. Layers depend on
protocols, never concrete types. This is what lets the on-device model be
swapped for a server model, MoveKit be swapped for another media source, a
second progression scheme be added alongside the first, and every layer be
tested against fakes.

**Extensible taxonomies, not closed enums.** `MuscleGroup`, `EquipmentType`,
`MovementPattern`, and `ExerciseCategory` are raw-value-backed structs with
static constants, in the style of `SwiftUI.Font.Weight` — not closed `enum`s. A
closed enum is the classic hardcoding trap when parsing external data: the day
the catalog gains a value, decoding either crashes or silently drops the entry.
Unknown values must round-trip intact.

**No magic numbers.** Rest defaults, rep ranges, set counts, and progression
thresholds live in a typed configuration loaded from data, with documented
defaults. No numeric literal that expresses a training opinion appears inside a
function body.

**Additive by default.** The catalog schema is versioned. New fields are
optional. Unknown JSON keys are ignored rather than fatal, so a catalog built by
a newer version does not break an older build.

**Every public type answers three questions.** What does it do, how is it used,
what does it depend on. If a type cannot be understood without reading its
internals, the boundary is wrong.

## Layers

Strict dependency direction. Each layer may import only those above it.

| Layer | Contents | Imports |
|---|---|---|
| `Domain/` | Pure value types and logic. `ExerciseID`, `Mass`, `MassUnit`, `RepRange`, `Tempo`, `RestInterval`, `RPE`, `MuscleGroup`, `EquipmentType`, `Mechanic`, `ForceType`, `ExerciseCategory`, `Exercise`, `ProgressionEngine`, `SetRecord`, `ExerciseHistory`. | Foundation only. No SwiftData. No SwiftUI. |
| `Catalog/` | `exercises.json`, `ExerciseCatalog` (lookup, search, filter, substitutes), `ExerciseResolver`. | Domain |
| `Store/` | SwiftData models. User data only. | Domain |
| `Services/` | `PlanGenerator`, `TemplatePlanBuilder`, `PlanCoordinator`, `PerformanceHistory`, `RestTimerModel`. | Domain, Catalog, Store |
| `Views/` | SwiftUI. | All of the above |

`Domain/` importing nothing but Foundation is what makes the interesting logic
testable without a database, a simulator, or a model. It is already true of
`ProgressionEngine`; this extends it to the whole core.

Folders enforce this by convention now. If it needs teeth later, each layer can
become a local SPM module and the compiler enforces it.

## Units: store what the lifter typed

`LoggedSet` stores `value: Double` **and** `unit: MassUnit` as entered.

The alternative — canonicalize everything to kilograms — loses fidelity. A lifter
who logged 135 lb should see 135 forever, not 61.23 kg rendered back as 134.99.
A logbook must never quietly alter the number someone wrote down.

Cross-unit math (charts, estimated 1RM, progression) uses a computed
`kilograms` property. Conversion happens at the point of comparison, never at
the point of storage.

`UserProfile.displayUnit` controls what new entries default to and how values
are presented. Changing it does not rewrite history.

## Store models

All user data, CloudKit-compatible.

- `UserProfile` — display unit, experience, available equipment, constraints and
  injuries, current goal.
- `BodyMetric` — bodyweight over time, so it is a tracked series rather than a
  single mutable field.
- `TrainingSchedule` — training days and session duration. Split out from the
  old `TrainingPreferences`, which mixed scheduling with identity.
- `WorkoutPlan` → `WorkoutSession` → `PlannedExercise` → `LoggedSet`.

`PlannedExercise` stores `exerciseID` (the slug) plus a denormalized
`displayName`. The denormalized copy means history stays readable if an exercise
is later renamed or removed from the catalog, while the ID remains the join key.

### CloudKit constraints

SwiftData's CloudKit backing imposes rules that shape every model, which is why
this is being done now rather than retrofitted:

- Every property is optional or has a default value.
- No `@Attribute(.unique)`. Uniqueness is enforced in application code.
- Every relationship is optional and has an inverse.
- Entitlements: iCloud with CloudKit, plus remote-notification background mode.

The container is configured with a private CloudKit database. A local-only
configuration stays available for tests and previews.

## Guarding generation against invented exercises

`PlanGenerator` continues to use Apple's on-device Foundation Model, but its
output is no longer trusted as canonical.

Generated exercise names pass through `ExerciseResolver`, which resolves to an
`ExerciseID` by exact match, then alias, then normalized match (case, hyphens,
punctuation, plural forms), then close fuzzy match above a confidence threshold.
Anything unresolved is replaced with a catalog exercise matching the intended
muscle group, equipment, and mechanic.

**An unresolved name is never persisted.** Every `PlannedExercise` in the store
points at a real catalog entry.

`TemplatePlanBuilder` is rewritten to select from the catalog by movement
pattern, equipment, and mechanic, replacing its hardcoded 37-name list. The
fallback path and the model path then draw from the same source of truth.

## Migration

None. The store is wiped and the schema starts clean — decided above. The app is
deleted and reinstalled on the device.

## Testing

The layer split exists to make this straightforward. Everything below is pure
and needs no simulator, database, or model:

- `Mass` conversion and rounding, including lb↔kg round trips.
- `ExerciseResolver` against a fixture table: exact, alias, normalized, fuzzy,
  and unresolvable inputs. This is the highest-value suite in the project — it is
  the guard on data integrity.
- `ExerciseCatalog` loading, lookup, search, and substitution.
- A catalog integrity test: all 412 IDs unique, no empty display names, every
  entry has at least one primary muscle and valid equipment.
- `ProgressionEngine` — existing suites, updated for `Mass`.
- `TemplatePlanBuilder` — returns only real catalog IDs, honors equipment.

## What this does not cover

- **Visual design.** Specified separately in
  `2026-08-14-modern-minimal-design-system.md`, now sequenced after this work.
- **Conversational onboarding.** Decisions recorded in that same document. Note
  that its references to `TrainingPreferences` now mean `UserProfile` plus
  `TrainingSchedule`, which replace it here.
- **Buying MoveKit animations.** The slot is designed; no purchase needed.

## Build order

1. This foundation.
2. Modern minimal design system.
3. Conversational onboarding.
