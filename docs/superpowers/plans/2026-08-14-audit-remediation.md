# Audit Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the defects three independent audits found, so the AI layer is
built on data and code that can be trusted.

**Architecture:** Fix the generator mechanism before the data it produced, and
add catalog versioning before changing any data — so corrections are detectable
rather than silently reinterpreting logged history.

**Tech Stack:** Swift 6, SwiftData, Swift Testing, Python 3 for the generator.

## Global Constraints

- Layer rule: `Domain/` imports Foundation only; `Catalog/` imports Domain; `Store/` imports Domain; `Services/` imports Domain, Catalog, Store; `Views/` imports all.
- Errors handled or propagated, never discarded. No `try?` that drops an error.
- No force unwrapping, force try, or force casting outside tests.
- **Data over code.** Training facts live in versioned JSON.
- Extensible taxonomies, not closed enums.
- Tests before implementation.
- Doc comments answer what/how-used/depends-on.
- Warnings are errors. Swift 6, strict concurrency.
- **`LiftingPlan/Catalog/Resources/exercises.json` is GENERATED. Never hand-edit.** Change `Tools/derivation-rules.json` or `Tools/overrides.json`, then:
  `python3 Tools/build-catalog.py --fedb /private/tmp/claude-501/-Users-jonluon-jonluongo/d714977f-a666-4255-994f-8d8f38cc2b32/scratchpad/fedb.json`
- **If an integrity test fails, the DATA is wrong. Never weaken an assertion.**
- The generator stays deterministic — two consecutive runs byte-identical.

**Build and test:**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 \
  | grep -E "Test run with|✘|error:"
```

**Two output traps.** `xcodebuild` prints `Test Suite 'All tests' passed.
Executed 0 tests` from the legacy XCTest reporter — expected, all tests are
Swift Testing; only `✔ Test run with N tests in M suites passed` proves
anything. And `CKAccountStatusNoAccount` CloudKit errors are expected — the
simulator has no iCloud account and the container degrades gracefully.

**Adding files:** `PBXFileSystemSynchronizedRootGroup` picks up new files under
`LiftingPlan/` automatically. Never hand-edit `project.pbxproj`; it spontaneously
rewrites itself (objectVersion 77 → 71), so revert with `git checkout --` before
committing — **but never revert `CODE_SIGN_ENTITLEMENTS` or
`INFOPLIST_KEY_UIBackgroundModes`**, which are intentional. Check `git diff`.

**Starting state:** 114 tests in 15 suites passing.

**Several agents on this project were killed by API errors near the end of long
runs. Commit as soon as work is green**, before optional polish.

---

## What the audits found

Three independent audits ran over the codebase. Architecture held up — zero
import violations across five layers. The defects are in data and in the
generator that produced it.

| Finding | Severity |
|---|---|
| 13 of 65 sampled catalog entries carry wrong data (~20%) | Critical |
| The slug matcher's substring collisions have now recurred **five times** | Critical — the mechanism, not the entries |
| No catalog versioning; correcting data silently reinterprets logged history | Important |
| `carry` missing from `compoundPatterns`, so every carry is tagged isolation | Important |
| Plan-hierarchy traversal duplicated in `Services/` and `Views/`, the `Views/` copy untested | Important |
| Four dead or vestigial items | Minor |

**Explicitly out of scope**, per the owner: adding exercises outside the 412.
The bodyweight vertical-press gap is a recorded product decision, not a defect —
see `docs/superpowers/specs/2026-08-14-catalog-enrichment-and-lifter-data.md`.

---

### Task 1: Catalog versioning — do this before touching any data

Correcting `barbell-spinal-jefferson-curl` from biceps to hamstrings changes
what a already-logged set *means*. With no version stamp there is no way to
detect that a plan was built against different data. Version first, then
correct.

**Files:**
- Modify: `Tools/build-catalog.py`, `LiftingPlan/Catalog/ExerciseCatalog.swift`, `LiftingPlan/Store/TrainingPlan.swift`
- Test: `LiftingPlanTests/CatalogIntegrityTests.swift`, `LiftingPlanTests/StoreModelTests.swift`

**Interfaces:**
- Produces: `ExerciseCatalog.version: Int`; `TrainingPlan.catalogVersion: Int`.

- [ ] **Step 1: Write the failing tests**

```swift
// CatalogIntegrityTests.swift
@Test("The bundled catalog declares a version")
func catalogDeclaresVersion() throws {
    #expect(try ExerciseCatalog.bundled().version >= 1)
}

// StoreModelTests.swift
@Test("A plan records which catalog version produced it")
func planStampsCatalogVersion() throws {
    let context = ModelContext(try StoreContainer.inMemory())
    context.insert(TrainingPlan(title: "Block", catalogVersion: 3))
    try context.saveOrThrow()
    let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
    #expect(loaded.catalogVersion == 3)
}
```

- [ ] **Step 2: Run and watch both fail.**

- [ ] **Step 3: Change the generated file's shape**

`exercises.json` is currently a bare array. Wrap it:

```json
{ "version": 1, "exercises": [ ... ] }
```

`ExerciseCatalog.bundled()` decodes the wrapper and exposes `version`. Keep
`init(exercises:)` for tests, defaulting version to 1.

**This changes the decoding contract**, so run the whole suite — several tests
decode the catalog. Any failure here is real, not noise.

- [ ] **Step 4: Bump the version in the generator**

Version lives in `Tools/build-catalog.py` as a module constant and is written
into the output. **Bump it in every later task in this plan that changes data**,
and say so in that task's commit message.

- [ ] **Step 5: Stamp it on `TrainingPlan`**

Add `var catalogVersion: Int = 1`, defaulted for CloudKit. When a plan is
created, record the catalog version that produced it. A later release can then
detect a plan built against older data.

- [ ] **Step 6: Run the suite and commit**

```sh
git add Tools LiftingPlan LiftingPlanTests
git commit -m "Version the exercise catalog and stamp it on plans"
```

---

### Task 2: Fix the matcher, not just its output

The rules match slug **substrings**, longest key wins. That has produced false
positives five separate times — `"lat"` inside `"plate"` and `"lateral"`,
`"ring"` inside `"hamstring"`, `"rope"` inside cable rope attachments, and now
`"curl"` matching `"jefferson-curl"`. Patching entries one at a time has not
worked because the mechanism is wrong.

**Files:**
- Modify: `Tools/build-catalog.py`
- Modify: `LiftingPlan/Catalog/Resources/exercises.json` (by regenerating)

**Interfaces:**
- Produces: word-boundary-aware `longest_match()`.

- [ ] **Step 1: Capture the current output as a baseline**

```sh
cp LiftingPlan/Catalog/Resources/exercises.json /tmp/catalog-before.json
```

- [ ] **Step 2: Make matching word-boundary aware**

Slugs are hyphen-delimited, so a key should match only on whole hyphen-separated
tokens, not on any character run. `"curl"` must match `barbell-curl` and
`dumbbell-preacher-curl`, but not `jefferson-curl`… **and that last case is the
subtlety: `jefferson-curl` DOES contain `curl` as a whole token.** Word
boundaries alone do not fix it.

So this task has two parts, and you must not conflate them:

**(a) Word-boundary matching** fixes the `"lat"`-in-`"plate"` class: match on
token boundaries so a key only matches whole hyphen-separated words. Implement
that in `longest_match()`.

**(b) The Jefferson curl needs an override**, because it is genuinely a
compound-word exception — "spinal jefferson curl" is not a curl in the
biceps sense even though it contains the token. Add it and its three siblings to
`overrides.json` in Task 3.

Be precise in your report about which entries (a) fixes versus which still need
(b). That distinction is the whole point of this task.

- [ ] **Step 3: Regenerate and diff EVERY change**

```sh
python3 Tools/build-catalog.py --fedb /private/tmp/claude-501/-Users-jonluon-jonluongo/d714977f-a666-4255-994f-8d8f38cc2b32/scratchpad/fedb.json
python3 - <<'PY'
import json
before = {e['id']: e for e in json.load(open('/tmp/catalog-before.json'))}
after_raw = json.load(open('LiftingPlan/Catalog/Resources/exercises.json'))
after = {e['id']: e for e in (after_raw['exercises'] if isinstance(after_raw, dict) else after_raw)}
changed = 0
for k in sorted(after):
    b, a = before.get(k, {}), after[k]
    diffs = {f: (b.get(f), a.get(f)) for f in
             ('pattern','equipment','primaryMuscles','secondaryMuscles','mechanic','category','difficulty')
             if b.get(f) != a.get(f)}
    if diffs:
        changed += 1
        print(k, diffs)
print('TOTAL CHANGED:', changed)
PY
```

**Read every single changed entry and judge it.** This is the highest-risk
change in the plan — tightening the matcher can silently *remove* a correct
match as easily as it removes a wrong one. For each change, state in your report
whether it is an improvement, a regression, or neutral. **If any change is a
regression, fix it before committing.**

- [ ] **Step 4: Run the suite, confirm determinism, commit**

Two consecutive generator runs must be byte-identical. Bump the catalog version.

```sh
git commit -m "Match rule keys on whole slug tokens, not character substrings"
```

---

### Task 3: Correct the wrong entries

**Files:**
- Modify: `Tools/derivation-rules.json`, `Tools/overrides.json`
- Modify: `LiftingPlan/Catalog/Resources/exercises.json` (by regenerating)
- Test: `LiftingPlanTests/CatalogIntegrityTests.swift`

**Confirmed wrong, verified directly:**

| Slug(s) | Currently | Should be |
|---|---|---|
| `barbell-spinal-jefferson-curl` and its bodyweight/dumbbell/kettlebell siblings | `pattern: curl`, `primaryMuscles: [biceps]` | a hinge-family movement on hamstrings and lower back — it is loaded spinal flexion, not a biceps curl |
| `kettlebell-turkish-get-up`, `kettlebell-farmers-carry`, `plate-pinch`, `dead-hang` | `mechanic: isolation` | `compound` — `carry` is missing from `compoundPatterns` |
| `barbell-upright-row`, `dumbbell-upright-row` | `pattern: horizontal pull` | a vertical/shoulder movement — the plane is wrong, which pollutes substitute suggestions |
| `jumping-jack`, `jump-rope` | `difficulty: advanced` | `beginner` — they inherit `advanced` from the plyometric pattern rule |

- [ ] **Step 1: Write failing assertions for each**

Add spot-check tests naming these exact slugs and expected values, so the
corrections are locked in rather than re-derivable by accident.

Also add a **class-level** guard: assert no exercise whose slug contains
`carry`, `hold`, `get-up`, or `farmer` is tagged `isolation`.

- [ ] **Step 2: Fix `carry` in the rules**

Add `"carry"` to `compoundPatterns` in `derivation-rules.json`. That is a rule
fix covering all carries at once, not four overrides.

- [ ] **Step 3: Fix the plyometric difficulty rule**

`difficultyByPattern` maps `plyometric` to `advanced`, which is wrong for
jumping jacks and skipping. Either drop `plyometric` from that table and let
box jumps take `advanced` from an override, or split the pattern. **Judge which
is right and explain your choice** — do not just special-case two slugs if the
rule itself is the problem.

- [ ] **Step 4: Override the genuine exceptions**

Jefferson curls and upright rows are per-exercise facts, so they belong in
`overrides.json`.

- [ ] **Step 5: Regenerate, diff against the previous state, run the suite**

Review every change as in Task 2. Bump the catalog version.

- [ ] **Step 6: Commit**

```sh
git commit -m "Correct thirteen miscategorized exercises"
```

---

### Task 4: Remove dead code and de-duplicate the history traversal

**Files:**
- Modify: `LiftingPlan/Views/HistoryView.swift`, `LiftingPlan/Services/PerformanceHistory.swift`, `LiftingPlan/Services/PlanBlueprint.swift`, `LiftingPlan/Services/TemplatePlanBuilder.swift`
- Create: `LiftingPlan/Services/ExerciseTrend.swift`
- Test: `LiftingPlanTests/ExerciseTrendTests.swift`

**Interfaces:**
- Produces: `ExerciseTrend` in `Services/`, sharing the hierarchy walk with `PerformanceHistory`.

- [ ] **Step 1: Move the trend logic out of the view**

`HistoryView` contains `ExerciseTrend.build` — best-set selection and an
improvement comparison. That is domain logic in a view file with **zero test
coverage**, and it re-walks the same plan → week → day → exercise hierarchy
`PerformanceHistory` already walks.

Move it to `Services/ExerciseTrend.swift`. Both it and `PerformanceHistory`
must share one traversal helper rather than each having their own — that
duplication is what let them drift.

- [ ] **Step 2: Write tests for it**

It has none. Cover: best-set selection across multiple sets, the improving
comparison, an exercise with no logged sets, and sets logged in **different
units** — the mixed-unit case is exactly where an untested comparison would
silently be wrong.

- [ ] **Step 3: Delete the dead items**

All four verified as unreferenced in production:

- `ExerciseBlueprint.muscleGroup` — written everywhere, read nowhere.
- `ExerciseBlueprint` itself — constructed only in tests. **Judge before deleting:** `PlanBlueprint.makeWorkoutPlan` is the mapping into SwiftData and will be needed by generation. If deleting the type would force generation to reinvent it, keep it and say why in your report.
- `TemplatePlanBuilder.splitTemplate` — called only by its own test. Same judgment: the assembly-rules work will need split templates. Decide whether to delete or leave with a comment naming the plan that will consume it.
- The `@Generable` `GeneratedExercise` schema in `PlanGenerator` — the model is asked for full exercise data on every call and the result is discarded. **Do not delete the type**, but stop requesting fields whose output is thrown away, so inference is not spent producing them. Report the change precisely.

- [ ] **Step 4: Run the full suite and commit**

```sh
git commit -m "Move trend logic into Services and remove dead code"
```

---

## Out of scope

- Adding exercises beyond the 412 — recorded product decision.
- The assembly-rules table, `EquipmentAccess` relocation, and progression
  constants — those belong with plan generation, which is the next plan.
- Wiring `ExerciseResolver` into generation — same.
- `UserProfile.bodyweight` / `BodyMetric` sync — neither has a write path yet;
  resolve it when the chat collects the data.
