# Open the Format — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Remove the restraints that stop Claude from coaching. Four parallel audits found no surviving app-side decision logic — the problem is that the shared vocabulary cannot express what a competent coach needs to say, and three things Claude reads are structurally always empty.

**Mission check:** the app supplements Claude with datakeeping and an interface. Every task below either *widens what can be recorded* or *closes a hole where a stated fact is dropped*. None adds logic that concludes anything about training.

## What the audits found

Clean, and worth stating so it is not re-audited: no tool recommends rather than reports; no schema carries a numeric bound; `write_plan` accepts `sets: 10`, `sets: 0`, negative rest and free-text `"AMRAP"` verbatim; absences stay `null` and never become `0`; truncation is disclosed; all seven catalog taxonomies round-trip unknown values byte-intact; CloudKit constraints hold across all eight models; `PlanImporter` and `makeWorkoutPlan` clamp and default nothing; protocol behaviour is correct against the real binary.

The findings are all of one shape: **the vocabulary is too narrow, and narrowness is silent.**

## Global Constraints

- **The app makes no training decisions and invents no values.** Widening the format must not smuggle in defaults.
- **Record what you are given** — and, new here: *refuse rather than discard*. Silently dropping an unknown key is worse than rejecting it, because Claude is told "Written" and believes the prescription landed.
- **Extensible taxonomies, not closed enums.** Unknown values round-trip intact.
- **Data over code.** No training opinion as a literal, a `static let`, or a stored-property default.
- Layers import only downward: LiftingKit → Store → Services → Views. LiftingKit may not import SwiftData or SwiftUI.
- Errors handled or propagated. No force unwrap/try/cast outside tests.
- Swift 6, strict concurrency, warnings are errors. Swift Testing, never XCTest.
- **Every format change is a versioned migration.** Both documents carry `version`; a reader must handle an older document rather than crashing on it.

**Baseline:** LiftingKit 156/15, LiftingMCP 125/13, app 126/16.

---

### Task 1: A block is more than one week

**The finding, across three audits.** `PlanDocument` has no per-week structure, but `write_plan` advertises `weekCount` — verified live that `weekCount: 8` is accepted, echoed back as success, and imported as a single `TrainingWeek(ordinal: 1)`. Seven weeks vanish silently. Meanwhile the snapshot side already reports `weekLabel` and `isDeload`, so **Claude can read a deload it can never write.**

This is the largest restraint in the system: no periodization, no wave loading, no deload, no progression across a block — the substance of programming.

- Give `PlanDocument` real weeks, each with its own days, label, and deload flag.
- `PlanImporter` maps them all. `TrainingPlan`/`TrainingWeek` already model this.
- Remove `weekCount` as a lie or make it derived — do not leave a field that is accepted and ignored.
- Version the format and keep single-week documents readable.
- The display side already handles multiple weeks (commit `77c7805`).

### Task 2: Per-set structure and intensity

**The finding.** One `sets`/`repRange`/`load` per exercise. No drop sets, ramping, back-off sets, per-set load, per-set notes. And no intensity target at all — no RPE, RIR, or %1RM — while `SnapshotLoggedSet.rpe` *is* logged and reported, so **prescribed effort can never be compared with achieved effort.**

- Let a prescribed exercise carry either a uniform prescription or an explicit per-set list.
- Add an intensity target that can express RPE, RIR, or %1RM without the app deciding which is meaningful.
- Keep the uniform case simple: the common prescription must not become verbose.

### Task 3: Stop discarding what Claude says

**The finding.** `write_plan` silently discards unknown keys — supersets, drop sets and per-set notes were all accepted and reported as "Written". `update_profile` silently drops `bodyweight`.

Silent discard is the worst failure mode in this system: Claude is told the prescription landed, the lifter never sees it, and nothing anywhere reports a problem.

- Unknown keys are **refused with the key named**, not dropped.
- Apply the same rule to every inbound document.

### Task 4: Bodyweight and baselines have no write path

**The finding.** Nothing in the app or either inbound document writes `bodyweight`, `bodyMetrics`, or `baselines` — yet `ContextReport` and `LogReportTools` read all three. Claude is permanently told the lifter has no bodyweight and no baselines, so **the first plan for any lift has no load anchor.**

- `update_profile` accepts bodyweight and strength baselines.
- Decide whether body metrics are a series Claude appends to; a single mutable number loses the trend the snapshot's own `BodyMetric` model was built for.

### Task 5: Equipment that matches reality

**The finding.** `Equipment` is four closed tiers. It cannot express "garage gym, no cables" — the audit measured the cost: forcing `.fullGym` grants 109 machine and cable exercises the lifter cannot do, while `.homeMinimal` denies all 66 barbell ones. Worse, an unknown `equipmentAccess` value **rejects the entire document**, violating the extensible-taxonomy standard at the exact point Claude is trying to record a fact.

- Model what the lifter actually owns as an open set of equipment types, not a tier.
- Keep tiers, if at all, as a convenience Claude may use — never as the only vocabulary.
- An unrecognized value must round-trip, not reject the document.

### Task 6: Smaller corrections

- `ExperienceLevel` is a closed enum that cannot express "returning after two years off", and duplicates the extensible `Difficulty` with different casing.
- `difficulty ?? .intermediate` fabricates an absence into a stated fact.
- `RepRange` parses `"30 seconds"` as 30 reps — a time-based set silently becomes a rep count.
- Epley's `30.0` is a training constant in Swift, duplicated in `LoggedSet.swift:49` and `StrengthBaseline.swift:39`.
- `RestTimerModel:43,140` discards notification authorization results and errors, so the rest cue fails permanently and silently.
- `TrainingPlan.swift:43` defaults `catalogVersion` to `1` while the catalog is at 5 — reintroducing the assumption `PlanBlueprint` explicitly refuses.
- Dead: `PerformanceHistory.histories(from:)`, `UserProfile.permits(...)`.

## Sequencing

1, 3, 2 first — the format and the refusal rule, since everything else writes through them. Then 4 and 5, which are new vocabulary. Then 6.

Re-verify all three suites and a device build after each task.

## Out of scope

- Supersets and circuits as *structure*. Task 2 covers per-set prescription; grouping exercises into a superset is a further change, and the audits did not establish that Claude needs it before the loop has been used in anger.
- Hosted MCP, OAuth, connectors.
