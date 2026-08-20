# The AI layer, rebuilt — design

**Status.** Phases 0, 1 and 2 are shipped — the read and write layer is done.
Phase 3 is **not** approved: it was raised as "think about it", it is the one
part that would put a form in front of the lifter, and the app's founding rule
is that it asks him nothing. See the note under it before building any of it.

**Goal.** One vocabulary for a prescription, one shape for the log, and reads
that are never quietly stale.

---

## What is wrong now

**A prescription exists in three vocabularies, and two of them disagree.**
`PlanDocument*` comes in, the `@Model`s store it, and `Snapshot*` reports it
back. The first and third are near-copies with one structural difference: a
document **nests** a group — `entries: [.exercise | .group]` — while the
snapshot **flattens** it into a `group` marker carried by each member. Same
fact, two encodings, two mapping layers, two test suites, and nothing but care
keeping them in step.

**The snapshot conflates a tree with a series.** A plan is a tree Claude wrote
once; a log is an append-only series of events. They are bundled, so every read
tool begins by flattening the tree back into a series — `TrainingLog.records(in:)`
is the first line of `exercise_history`, `recent_sessions`, `volume_by_muscle`
and half the context resource. The flat series is the shape everything wants;
the nesting is the shape nothing wants.

**Freshness was the third fault** and is fixed: the snapshot now goes out when a
session is finished or taken back and when one of Claude's documents lands, not
only when the app backgrounds (`6552818`).

---

## The shape

```
TrainingSnapshot (version 3)
  version, catalogVersion, generatedAt
  profile, bodyMetrics, baselines          — unchanged
  routines: [SnapshotRoutine]
  log: [LoggedSetRecord]

SnapshotRoutine
  document: PlanDocument                   — exactly what Claude wrote
  startDate: Date                          — when the app took it in
  completedAt: Date?                       — superseded; never "he finished it"
  sessions: [SnapshotSession]              — what the record knows per prescribed day

SnapshotSession
  weekOrdinal: Int, weekday: Weekday, completedAt: Date?

LoggedSetRecord
  routineID: UUID                          — the document's id
  weekOrdinal: Int, weekday: Weekday
  exerciseOrder: Int                       — position within the day, which is identity
  exerciseID: ExerciseID                   — what it is, which is what gets filtered on
  setIndex: Int, isWarmup: Bool, isCompleted: Bool, completedAt: Date
  load: Mass?, reps: Int, durationSeconds: Int?, distance: Distance?
```

`Snapshot{Plan,Week,Day,PlannedExercise,ExerciseGroup,LoggedSet}` are deleted.

**Why the document travels whole.** It removes the third vocabulary and with it
the flat/nested disagreement — a group is described once, by the format that
prescribed it. It also makes "did my plan land?" answerable by comparison rather
than interpretation. `PlanDocument(reconstructing:)` and its round-trip suite
(`938e2f7`) are what make this honest: the store holds every field the document
states, proven rather than asserted.

**Why the log is flat.** Every question asked of it is a filter, a group-by or a
sort. The prescription for any logged set is found by
`routineID → document → weeks[weekOrdinal - 1] → days.first(weekday) →
exercises[exerciseOrder] → prescribedSets[setIndex]`; `exerciseOrder` is what
disambiguates a movement prescribed twice in one day.

---

## The work, in order

**Phase 0 — freshness. Shipped** (`6552818`), with the version-skew guard the
cutover needs (`e96af66`) and the round-trip proof (`938e2f7`).

**Phase 1 — the format and the exporter.** One commit, because a half-moved
format is a fourth vocabulary. LiftingKit gains the types above and drops the
five; `SnapshotExporter` becomes *reconstruct each routine's document, stamp
what the store knows, append the log*; MCP's `TrainingLog` reads `snapshot.log`
directly and `records(in:)` disappears.

**Phase 2 — the tools. Shipped** with phase 1, except `displayName`, which
landed after (`PlanDocument.named(using:)`). `exercise_history` is a filter, `recent_sessions` a
group-and-sort, `volume_by_muscle` a windowed join against the catalog. The
context resource keeps its exact shape: it is the contract Claude already reads.
The four field removals from the 2026-08-19 audit fold in here rather than
costing their own version bump — `inCatalog` (a literal `true`), `SnapshotPlan.
generatedAt` (nothing reads it), `displayName` on `write_plan` (the server links
the catalog that owns the name), `weekCount` (derivable, and can disagree).

**Phase 3 — the account. Not built, and not to be built unasked.** The rule it
runs into is the app's first one: *there is no setup screen and no settings form
for a training question*. An editable box is defensible — a box that shows and
lets you correct is not a form that asks — but it is a reversal of a stated
decision and needs to be made deliberately, not inferred from a maybe.
`bfb3caa` shipped the half of it that has no such problem: the lifter writes his
own note on an exercise, in a field of its own, and it reaches the coach.

If it is wanted: two editable facts, not eight —
**bodyweight** (a number he knows, a dated series, an edit is an append) and
**injuries/constraints** (the one fact where waiting for a conversation actually
harms training). Everything else stays Claude's. The real work is provenance:
`StatedValue` carrying who last said a fact and when, so `update_profile` does
not silently overwrite what the lifter typed, and the snapshot reporting it.

---

## What must not change

Load-bearing, and each has been paid for once already:

- **The stateless macOS server.** No database, no sync logic, no migrations off
  the phone. Every tool is a pure function of one file.
- **The iCloud folder as the only channel**, symmetric in both directions.
- **Refuse-unknown-key-whole, with the key named**, shared through
  `DocumentRefusal` so the phone and the server cannot answer differently.
- **Per-document versions, skew refused rather than guessed.**
- **The catalog as shared vocabulary**, identity the MoveKit slug, `write_plan`
  refusing an ID the catalog lacks.
- **Two write tools, not one** — a prescription and facts about a lifter are
  different in kind.
- **A small always-attached resource plus drill-down tools.**
- **No tool that concludes.** No `suggest_progression`, no readiness score.

## Deployment

The phone and the server are installed separately, so there is a window where
one is ahead of the other. Version skew is refused whole rather than guessed, so
that window is loud rather than silent — a v2 server reading a v3 snapshot says
so and names both versions instead of reporting a lifter who has never trained.
Install the app build and rebuild the MCP server in the same sitting.
