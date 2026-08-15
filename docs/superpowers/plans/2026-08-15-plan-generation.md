# Plan Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `TemplatePlanBuilder.build` produce a real, balanced, equipment-legal week of training from the 412-exercise catalog, replacing the `PlanBlueprint(days: [])` it returns today.

**Architecture:** The app owns the skeleton — split, slot count, pattern per slot, balance rules — as versioned JSON. A deterministic selector fills each slot from the catalog, filtered by the lifter's equipment access. Nothing about training is expressed as a numeric literal inside a function body. The on-device model's output, when present, passes through `ExerciseResolver` before it can become an `ExerciseID`.

**Tech Stack:** Swift 6 (strict concurrency, warnings-as-errors), Swift Testing, SwiftData/CloudKit, bundled JSON reference data.

**Implements:** `docs/superpowers/specs/2026-08-14-workout-programming-design.md` (approved, unchanged).
**Context:** `docs/superpowers/specs/2026-08-15-mcp-coaching-architecture-design.md` explains why this is the prerequisite for everything else.

## Global Constraints

Copied from `CLAUDE.md`; every task's requirements implicitly include these.

- **Layers import only downward:** `Domain/` (Foundation only) → `Catalog/` (Domain) → `Store/` (Domain) → `Services/` (Domain, Catalog, Store) → `Views/` (all). This is the most important rule in the project.
- **Data over code.** No numeric literal expressing a training opinion appears inside a function body. Splits, slot counts, rep ranges, rest, set counts, and balance rules live in versioned JSON.
- **Errors are handled or propagated, never discarded.** No `try?` that drops an error.
- **No force unwrapping, force try, or force casting** outside tests.
- **Extensible taxonomies, not closed enums.** Unknown values round-trip intact.
- **Protocol seams at boundaries.**
- **Every public type's doc comment answers three questions:** what it does, how it is used, what it depends on.
- **Warnings are errors.** Swift 6 language mode, strict concurrency.
- **Files stay focused.** Past ~300 lines is a signal of doing too much.
- **Tests are Swift Testing** (`@Test`, `#expect`, `#require`), never XCTest. Only `✔ Test run with N tests in M suites passed` proves tests ran; `** TEST SUCCEEDED **` proves nothing.
- **Never hand-edit** `LiftingPlan/Catalog/Resources/exercises.json` (generated) or `project.pbxproj`.

**Baseline at plan start:** 139 tests in 18 suites passing, catalog version 5, 412 exercises.

**Standing environment hazard:** the volume has hit ENOSPC repeatedly because a connected iPhone causes Xcode to refill an ~8.3GB device symbol cache. On "No space left on device", STOP and report — do not self-remediate.

---

### Task 1: Assembly rules as bundled data

**Files:**
- Create: `LiftingPlan/Catalog/Resources/assembly-rules.json`
- Create: `LiftingPlan/Catalog/AssemblyRules.swift`
- Modify: `CLAUDE.md` (Catalog layer description)
- Test: `LiftingPlanTests/AssemblyRulesTests.swift`

**Interfaces:**
- Produces: `AssemblyRules` (decoded reference data), `AssemblyRulesProviding` protocol with `static func bundled() throws -> AssemblyRules`, `var version: Int`.

`Catalog/` is currently described as "bundled exercise reference data." Assembly rules are bundled *programming* reference data with identical lifecycle — versioned, gated, loaded once. Generalize the layer's charter to "bundled reference data" rather than inventing a layer for one file. Update the table in `CLAUDE.md` accordingly.

**Version the file exactly as the catalog is versioned** (`{"version": 1, ...}`), and expose `version` on the protocol — not only the concrete type. The catalog's `version` was omitted from `ExerciseCatalogProviding` and that omission was the direct cause of a Critical review finding.

- [ ] **Step 1: Write the failing tests first**

Cover: every day count 1–6 yields a split; every slot names a role and a pattern; rep ranges parse via `RepRange`; rest and set values are positive; the file's `version` is exposed through the protocol; a fake conforming to `AssemblyRulesProviding` can vary `version`.

- [ ] **Step 2: Author `assembly-rules.json`**

Shape (values below are the starting prescription, drawn from the programming spec — every number in this file is a training opinion and belongs here rather than in Swift):

```json
{
  "version": 1,
  "splitsByDayCount": {
    "1": [{ "focus": "Full Body", "slots": ["primary:squat", "secondary:horizontal press", "secondary:horizontal pull", "accessory:hinge"] }],
    "2": [{ "focus": "Full Body", "slots": ["..."] }, { "focus": "Full Body", "slots": ["..."] }],
    "3": [{ "focus": "Push" }, { "focus": "Pull" }, { "focus": "Legs" }],
    "4": [{ "focus": "Upper Body" }, { "focus": "Lower Body" }, { "focus": "Upper Body" }, { "focus": "Lower Body" }],
    "5": ["..."],
    "6": ["..."]
  },
  "slotCountByDurationMinutes": [
    { "upTo": 30, "slots": 3 },
    { "upTo": 45, "slots": 4 },
    { "upTo": 60, "slots": 5 },
    { "upTo": 999, "slots": 6 }
  ],
  "byRole": {
    "primary":   { "sets": 4, "reps": "4-6",   "restSeconds": 180 },
    "secondary": { "sets": 3, "reps": "6-10",  "restSeconds": 120 },
    "accessory": { "sets": 3, "reps": "10-15", "restSeconds": 60 },
    "finisher":  { "sets": 2, "reps": "12-20", "restSeconds": 45 }
  },
  "setAdjustmentByExperience": { "beginner": -1, "intermediate": 0, "advanced": 1 },
  "balanceRules": [
    { "atLeast": "horizontal pull", "comparedTo": "horizontal press" },
    { "atLeast": "vertical pull",   "comparedTo": "vertical press" }
  ],
  "requiredWeeklyPatterns": ["squat", "hinge"],
  "maxShareOfSessionPerPattern": 0.5
}
```

Every split must target each major pattern at least twice per week — that is the property the programming spec identifies as the thing muscle-group splits get wrong, and Task 2 asserts it.

- [ ] **Step 3: Write `AssemblyRules.swift`**

Decode leniently in the same spirit as `Exercise`: an unrecognized role or pattern string must round-trip rather than crash, per the extensible-taxonomy standard. Reuse `MovementPattern` and `RepRange` from `Domain/` — do not re-parse rep strings.

- [ ] **Step 4: Run the tests, then commit**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test run with|✘|error:"
git commit -m "Add assembly rules as versioned bundled data"
```

---

### Task 2: Session skeleton assembly

**Files:**
- Create: `LiftingPlan/Services/SessionSkeleton.swift`
- Test: `LiftingPlanTests/SessionSkeletonTests.swift`

**Interfaces:**
- Consumes: `AssemblyRules` from Task 1.
- Produces:
```swift
struct SlotSpec: Sendable, Equatable {
    let role: SlotRole          // primary | secondary | accessory | finisher
    let pattern: MovementPattern
    let sets: Int
    let reps: RepRange
    let restSeconds: Int
}
struct SessionSpec: Sendable, Equatable {
    let weekday: Weekday
    let focus: String
    let slots: [SlotSpec]
}
enum SessionSkeleton {
    static func build(weekdays: [Weekday], durationMinutes: Int,
                      experience: ExperienceLevel, rules: AssemblyRules) -> [SessionSpec]
}
```

**No catalog, no equipment, no exercises.** This task decides *shape only* — which day trains what, how many slots, which pattern and prescription each slot carries. Keeping it exercise-free is what makes the balance properties testable without a database or a model.

- [ ] **Step 1: Write the failing tests**

Assert the properties, not the literals:
- Every major pattern appears **at least twice across the week**, for every day count 1–6.
- No pattern occupies more than `maxShareOfSessionPerPattern` of any one session.
- Slot count follows the duration table; a 30-minute session gets fewer slots than a 60-minute one.
- Slots are ordered by neurological demand: `primary` first, `finisher` last.
- Experience adjusts set counts and never produces fewer than 1 set.
- Same inputs produce identical output (determinism).

- [ ] **Step 2: Implement**

Read every number from `rules`. If a literal integer expressing a training opinion appears in this file, the task has failed its main constraint.

- [ ] **Step 3: Run the tests and commit**

---

### Task 3: Equipment-filtered exercise selection

**Files:**
- Create: `LiftingPlan/Services/ExerciseSelector.swift`
- Test: `LiftingPlanTests/ExerciseSelectorTests.swift`

**Interfaces:**
- Consumes: `SessionSpec` (Task 2), `ExerciseCatalogProviding`, `EquipmentAccess`.
- Produces:
```swift
struct SelectedSlot: Sendable, Equatable {
    let spec: SlotSpec
    let exercise: ExerciseID?   // nil when the pattern has no legal option
}
struct ExerciseSelector: Sendable {
    init(catalog: ExerciseCatalogProviding)
    func fill(_ sessions: [SessionSpec], equipment: Equipment,
              avoiding: Set<ExerciseID>, avoidingPatterns: Set<MovementPattern>) -> [[SelectedSlot]]
}
```

- [ ] **Step 1: Write the failing tests**

The critical cases, in priority order:

1. **A pattern with zero legal options yields `nil`, never a substitute the lifter cannot perform, and never a crash.** The foundation spec records that a bodyweight-only lifter has **zero** vertical-press options and exactly **one** horizontal pull. This is a normal case, not an error.
2. **Every selected exercise is permitted by the lifter's `EquipmentAccess` tier.** Assert across all tiers, over the real bundled catalog — not a fixture.
3. **Selection is deterministic**: same inputs, same `ExerciseID`s, across repeated runs. Tie-break explicitly on lowest `id.rawValue`; a `Dictionary` iteration order tie-break already caused a real nondeterminism bug in this codebase.
4. **No exercise repeats within a session.**
5. `avoiding` and `avoidingPatterns` are respected (injury constraints).
6. Compound movements are preferred for `primary` and `secondary` roles; isolation for `accessory`.

- [ ] **Step 2: Implement**

Filter first by `EquipmentAccess.permitted(for:)`, then by pattern, then by role suitability, then apply the deterministic tie-break. **`permitted(for:)` currently has no production consumer — this task is what makes the equipment gate real rather than theoretical.**

- [ ] **Step 3: Run the tests and commit**

---

### Task 4: Balance validation and deterministic repair

**Files:**
- Create: `LiftingPlan/Services/BalanceValidator.swift`
- Test: `LiftingPlanTests/BalanceValidatorTests.swift`

**Interfaces:**
- Produces:
```swift
struct BalanceViolation: Sendable, Equatable { let rule: String; let detail: String }
enum BalanceValidator {
    static func validate(_ week: [[SelectedSlot]], rules: AssemblyRules) -> [BalanceViolation]
    static func repair(_ week: [[SelectedSlot]], rules: AssemblyRules,
                       selector: ExerciseSelector, equipment: Equipment) -> [[SelectedSlot]]
}
```

- [ ] **Step 1: Write the failing tests**

- A week with 4 horizontal presses and 1 horizontal pull is reported as violating.
- A balanced week reports no violations.
- **`repair` produces a week that `validate` passes** — the round-trip property is the real test.
- **A rule that cannot be satisfied because the pattern has zero legal options does NOT report a violation.** A bodyweight-only lifter must not fail a vertical-pull-≥-vertical-press check when neither pattern is available to them. Getting this wrong makes bodyweight plans permanently unrepairable.
- `repair` is deterministic and terminates — assert it does not loop.

- [ ] **Step 2: Implement**

Rules come from `rules.balanceRules`, not from conditionals naming patterns.

- [ ] **Step 3: Run the tests and commit**

---

### Task 5: Wire the deterministic path end to end

**Files:**
- Modify: `LiftingPlan/Services/TemplatePlanBuilder.swift`
- Modify: `LiftingPlan/Services/PlanBlueprint.swift` (only if the mapping needs new fields)
- Test: `LiftingPlanTests/TemplatePlanBuilderTests.swift`

**Interfaces:**
- Consumes: Tasks 1–4.
- `TemplatePlanBuilder.build` gains the catalog and rules it needs. Follow the precedent set by the `catalogVersion` fix: **required parameters, no defaults** — a default is what let a missing value ship silently before.

- [ ] **Step 1: Write the failing tests**

- `build` returns a plan with **at least one exercise per day** for every equipment tier and every day count 1–6. This is the test that fails today.
- Every returned exercise resolves to a real catalog entry.
- The result passes `BalanceValidator.validate`.
- A bodyweight-only lifter gets a usable plan with no empty-slot crash and no illegal exercise.

- [ ] **Step 2: Delete `splitTemplate`**

Its `switch` over day count returning focus strings is precisely the data-over-code violation the programming spec calls out. The split data now lives in `assembly-rules.json`. Remove the function and its test; do not leave it orphaned.

- [ ] **Step 3: Implement, run the full suite, commit**

---

### Task 6: Sticky exercise selection across regeneration

**Files:**
- Create: `LiftingPlan/Services/StickySelection.swift`
- Test: `LiftingPlanTests/StickySelectionTests.swift`

**Interfaces:**
- Consumes: existing `[TrainingPlan]` history, `ExerciseSelector`.
- Produces: `static func preserving(_ previous: TrainingPlan?, into week: [[SelectedSlot]]) -> [[SelectedSlot]]`

The programming spec calls this "the most important rule for this app specifically, and the easiest to get wrong."

- [ ] **Step 1: Write the failing tests**

- Regenerating with unchanged inputs returns **the same exercises**, with only sets/reps/load free to change.
- The exercise list changes only when equipment changes, the lifter asks for a swap, or a training day is added or removed.
- A swap uses `ExerciseCatalog.substitutes(for:)` so the replacement shares the movement pattern and the slot's purpose survives.
- A slot whose previous exercise is no longer equipment-legal is re-selected rather than kept.

- [ ] **Step 2: Implement, run tests, commit**

---

### Task 7: Route model output through `ExerciseResolver`

**Files:**
- Modify: `LiftingPlan/Services/PlanGenerator.swift`
- Test: `LiftingPlanTests/PlanGeneratorResolutionTests.swift`

`ExerciseResolver` is the most thoroughly tested code in the project and **has never been called by production code.** The model may name exercises in free text; nothing may become an `ExerciseID` without passing through it.

- [ ] **Step 1: Write the failing tests**

- A model-proposed name that resolves is used.
- A name that does **not** resolve is rejected and the slot falls back to deterministic selection — never invented, never dropped silently.
- A resolved exercise that is not equipment-legal for this lifter is rejected. The model does not get to override the equipment gate.
- The deterministic path remains reachable and produces the same quality of plan when the model is unavailable.

- [ ] **Step 2: Implement, run the full suite, commit**

---

## Self-review notes

- **Spec coverage:** pattern-based organization (T2), balance constraints (T4), session structure ordering (T2), weekly templates as JSON (T1), sticky selection (T6), `TemplatePlanBuilder` rewritten and `splitTemplate` deleted (T5), model narrowed to filling slots with resolver validation (T7). All sections of the programming spec map to a task.
- **Zero-option patterns** are addressed in T3, T4, and T5 rather than once, because the foundation spec records them as a permanent property of the frozen catalog rather than a defect.
- **Type consistency:** `SlotSpec`/`SessionSpec` (T2) → `SelectedSlot` (T3) → consumed unchanged by T4, T5, T6.

## Out of scope

- The shared Swift package and MCP server — separate plan, follows this one.
- Load prescription from `StrengthBaseline`; neither it nor `BodyMetric` has a write path yet, so plans prescribe sets and reps without weight and the first session establishes the baseline.
- Any in-app chat UI.
