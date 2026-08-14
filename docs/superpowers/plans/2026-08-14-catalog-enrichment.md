# Catalog Enrichment and Lifter Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give plan generation the data it needs — secondary muscles on every
exercise, a difficulty rating, and the lifter facts required to prescribe a
starting weight.

**Architecture:** Catalog gaps are closed by extending the declarative
derivation rules and regenerating, never by hand-editing generated output.
Lifter gaps are closed by extending `UserProfile` and adding two small
CloudKit-compatible models.

**Tech Stack:** Swift 6, SwiftData with CloudKit, Swift Testing, Python 3 for
the offline catalog generator.

## Global Constraints

From `CLAUDE.md` and
`docs/superpowers/specs/2026-08-14-catalog-enrichment-and-lifter-data.md`.

- A layer may import only the layers above it. `Domain/` imports Foundation only; `Catalog/` imports Domain; `Store/` imports Domain; `Services/` imports Domain, Catalog, Store; `Views/` imports all.
- Errors are handled or propagated, never discarded. No `try?` that drops an error.
- No force unwrapping, force try, or force casting outside tests.
- **Data over code.** Training facts live in versioned JSON, never in Swift control flow.
- Extensible taxonomies, not closed enums. Unknown values round-trip intact.
- Tests before implementation.
- Every public type's doc comment answers: what it does, how it is used, what it depends on.
- Warnings are errors. Swift 6 language mode, strict concurrency.
- Files stay focused; past roughly 300 lines is a signal.
- **CloudKit:** every property optional or defaulted, no `@Attribute(.unique)`, every relationship optional with an inverse.
- **`LiftingPlan/Catalog/Resources/exercises.json` is GENERATED.** Never hand-edit it. Fix data in `Tools/derivation-rules.json` or `Tools/overrides.json`, then regenerate:
  `python3 Tools/build-catalog.py --fedb /private/tmp/claude-501/-Users-jonluon-jonluongo/d714977f-a666-4255-994f-8d8f38cc2b32/scratchpad/fedb.json`

**Build and test command:**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 \
  | grep -E "Test run with|✘|error:"
```

**Reading test output — trap.** `xcodebuild` prints `Test Suite 'All tests'
passed. Executed 0 tests` from the legacy XCTest reporter. Expected; all tests
here are Swift Testing. `** TEST SUCCEEDED **` alone does not prove tests ran —
only `✔ Test run with N tests in M suites passed` does.

You will also see CloudKit errors like `Unable to initialize without an iCloud
account (CKAccountStatusNoAccount)`. **Expected and harmless** — the simulator
has no iCloud account, the container degrades gracefully. Not a failure.

**Adding files:** the project uses `PBXFileSystemSynchronizedRootGroup`. Files
created under `LiftingPlan/` are picked up automatically. Never hand-edit
`project.pbxproj` to add sources. It also spontaneously rewrites itself
(objectVersion 77 → 71) on this machine; revert with `git checkout --` before
committing, but **do not revert `CODE_SIGN_ENTITLEMENTS` or
`INFOPLIST_KEY_UIBackgroundModes`** — those are intentional. Check `git diff`
first.

**Starting state:** 102 tests in 14 suites passing.

**Rule that governs every task here:** if an integrity test fails, the DATA is
wrong. Fix the rules and regenerate. Never weaken an assertion.

**Two agents on this project were killed by API errors near the end of long
runs.** Commit incrementally rather than saving one commit for the end.

---

## The measured gaps

| Field | Coverage | Consequence |
|---|---|---|
| `secondaryMuscles` | 64/412 (15%) | Nothing can compute weekly volume per muscle. Bench + overhead press + dips + extensions reads as balanced; it is four triceps exercises. |
| difficulty | 0/412 — no field | Selection cannot match the lifter's experience. |
| bodyweight | not recorded | Cannot prescribe load for bodyweight-relative work. |
| current strength | not recorded | **A first plan cannot suggest any starting weight.** |
| constraints | free text only | An injury can be read but not enforced as a filter. |

---

## File Structure

| File | Responsibility |
|---|---|
| `Tools/derivation-rules.json` | Gains `patternSecondaryMuscles` and the difficulty tables. |
| `Tools/build-catalog.py` | Applies them; unchanged in shape. |
| `LiftingPlan/Domain/Taxonomies.swift` | Gains `Difficulty`. |
| `LiftingPlan/Domain/Exercise.swift` | Gains `difficulty`. |
| `LiftingPlan/Store/UserProfile.swift` | Gains `bodyweight`, `avoidedPatterns`, `avoidedExercises`. |
| `LiftingPlan/Store/BodyMetric.swift` | Bodyweight over time. |
| `LiftingPlan/Store/StrengthBaseline.swift` | What the lifter can currently lift. |
| `LiftingPlan/Store/StoreContainer.swift` | Registers the two new models. |
| `LiftingPlanTests/CatalogIntegrityTests.swift` | Gains secondary-muscle and difficulty gates. |
| `LiftingPlanTests/LifterDataTests.swift` | The new models. |

---

### Task 1: Secondary muscles for every exercise

**Files:**
- Modify: `Tools/derivation-rules.json`
- Modify: `LiftingPlan/Catalog/Resources/exercises.json` (by regenerating)
- Modify: `LiftingPlanTests/CatalogIntegrityTests.swift`

**Interfaces:**
- Consumes: the existing generator.
- Produces: `secondaryMuscles` populated on the large majority of entries. Consumed by plan generation later.

- [ ] **Step 1: Write the failing integrity test**

Add to `CatalogIntegrityTests.swift`:

```swift
@Test("Compound resistance exercises name the muscles they work beyond the prime mover")
func secondaryMusclesPresent() throws {
    let catalog = try ExerciseCatalog.bundled()
    let needsSecondary = catalog.all.filter {
        $0.isResistanceTraining && $0.mechanic == .compound
    }
    let missing = needsSecondary.filter { $0.secondaryMuscles.isEmpty }
    #expect(missing.isEmpty,
            "compound exercises with no secondary muscles: \(missing.map(\.id.rawValue).sorted())")
}

@Test("Known exercises name the specific muscles a lifter would expect")
func secondaryMusclesAreCorrect() throws {
    let catalog = try ExerciseCatalog.bundled()

    func secondaries(_ id: String) throws -> Set<MuscleGroup> {
        let exercise = try #require(catalog.exercise(id: ExerciseID(rawValue: id)),
                                    "\(id) missing from catalog")
        return Set(exercise.secondaryMuscles)
    }

    // A bench press works triceps and front delts. This is the case that
    // motivated the whole task.
    #expect(try secondaries("barbell-bench-press").contains(.triceps))
    #expect(try secondaries("barbell-bench-press").contains(.shoulders))
    // A pulldown works biceps.
    #expect(try secondaries("lat-pulldown").contains(.biceps))
    // A squat works glutes.
    #expect(try secondaries("barbell-squat").contains(.glutes))
}

@Test("A muscle is never both the prime mover and a secondary")
func primaryAndSecondaryStayDisjoint() throws {
    for exercise in try ExerciseCatalog.bundled().all {
        #expect(Set(exercise.primaryMuscles).isDisjoint(with: Set(exercise.secondaryMuscles)),
                "\(exercise.id) lists a muscle as both primary and secondary")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LiftingPlanTests/CatalogIntegrityTests test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: `secondaryMusclesPresent` and `secondaryMusclesAreCorrect` fail, naming
a long list of slugs. That list is the work.

- [ ] **Step 3: Add the pattern table to `derivation-rules.json`**

Add a `patternSecondaryMuscles` key alongside the existing `patternMuscles`:

```json
"patternSecondaryMuscles": {
  "horizontal press": ["triceps", "shoulders"],
  "vertical press": ["triceps"],
  "horizontal pull": ["biceps", "shoulders"],
  "vertical pull": ["biceps", "middle back"],
  "squat": ["glutes", "hamstrings", "lower back"],
  "hinge": ["lower back", "traps"],
  "lunge": ["glutes", "hamstrings"],
  "fly": ["shoulders"],
  "shrug": ["forearms"],
  "curl": ["forearms"],
  "carry": ["forearms", "traps"],
  "olympic": ["glutes", "hamstrings", "traps", "shoulders"],
  "plyometric": ["glutes", "calves"],
  "rotation": ["abdominals"],
  "flexion": ["abdominals"]
}
```

Deliberately omitted: `extension`, `raise`, `stretch`, `cardio`. Triceps
pushdowns and lateral raises are genuine single-muscle isolations, and inventing
secondaries for them would be worse than leaving them empty.

- [ ] **Step 4: Apply it in the generator**

In `Tools/build-catalog.py`, where `secondary` is currently initialized to an
empty list before enrichment, seed it from the pattern table instead:

```python
secondary = list(rules.get("patternSecondaryMuscles", {}).get(pattern, []))
```

Precedence must not change: this is the *default*. free-exercise-db enrichment
still overwrites it for matched entries, and `overrides.json` still wins over
both. Do not reorder those.

The existing post-override deduplication already removes any muscle that is also
primary — verify it still runs after `entry.update(overrides[slug])`.

- [ ] **Step 5: Regenerate and inspect**

```sh
python3 Tools/build-catalog.py --fedb /private/tmp/claude-501/-Users-jonluon-jonluongo/d714977f-a666-4255-994f-8d8f38cc2b32/scratchpad/fedb.json
python3 -c "
import json
c = json.load(open('LiftingPlan/Catalog/Resources/exercises.json'))
print('entries:', len(c))
print('with secondaries:', sum(1 for e in c if e.get('secondaryMuscles')))
print('overlaps:', sum(1 for e in c if set(e['primaryMuscles']) & set(e.get('secondaryMuscles', []))))
for s in ['barbell-bench-press', 'lat-pulldown', 'barbell-squat']:
    e = next(x for x in c if x['id'] == s)
    print(' ', s, e['primaryMuscles'], '->', e['secondaryMuscles'])
"
```

Expected: 412 entries, secondaries on the large majority, **zero overlaps**, and
bench press showing triceps and shoulders.

- [ ] **Step 6: Run the tests**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test run with|✘|error:"
```

If `secondaryMusclesPresent` still names slugs, read them. Each is either a
pattern missing from the table, or a genuine isolation that should be excluded
from the test's filter. **Judge which, and say why in your report** — do not
blanket-exclude to force green.

- [ ] **Step 7: Commit**

```sh
git add Tools LiftingPlan/Catalog/Resources/exercises.json LiftingPlanTests/CatalogIntegrityTests.swift
git commit -m "Derive secondary muscles from movement pattern"
```

---

### Task 2: Difficulty

**Files:**
- Modify: `LiftingPlan/Domain/Taxonomies.swift`, `LiftingPlan/Domain/Exercise.swift`
- Modify: `Tools/derivation-rules.json`, `Tools/build-catalog.py`
- Modify: `LiftingPlan/Catalog/Resources/exercises.json` (by regenerating)
- Test: `LiftingPlanTests/CatalogIntegrityTests.swift`, `LiftingPlanTests/TaxonomyTests.swift`

**Interfaces:**
- Consumes: `ExtensibleTaxonomy`.
- Produces: `struct Difficulty: ExtensibleTaxonomy` with `.beginner`, `.intermediate`, `.advanced`; `Exercise.difficulty: Difficulty`.

- [ ] **Step 1: Write the failing tests**

In `CatalogIntegrityTests.swift`:

```swift
@Test("Every exercise carries a difficulty this build recognizes")
func difficultyPresentAndKnown() throws {
    for exercise in try ExerciseCatalog.bundled().all {
        #expect(exercise.difficulty.isKnown,
                "\(exercise.id) has unrecognized difficulty \(exercise.difficulty)")
    }
}

@Test("Difficulty matches what a lifter would expect for known movements")
func difficultyIsSensible() throws {
    let catalog = try ExerciseCatalog.bundled()
    func difficulty(_ id: String) throws -> Difficulty {
        try #require(catalog.exercise(id: ExerciseID(rawValue: id))).difficulty
    }
    // An Olympic lift is not a beginner movement.
    #expect(try difficulty("power-clean") == .advanced)
    // A machine isolation is.
    #expect(try difficulty("machine-hip-abduction") == .beginner)
}
```

In `TaxonomyTests.swift`, mirroring the existing taxonomy tests:

```swift
@Test("Difficulty decodes known values and preserves unknown ones")
func difficultyTaxonomy() throws {
    #expect(try JSONDecoder().decode(Difficulty.self, from: Data("\"advanced\"".utf8)) == .advanced)
    let exotic = try JSONDecoder().decode(Difficulty.self, from: Data("\"elite\"".utf8))
    #expect(exotic.rawValue == "elite")
    #expect(!exotic.isKnown)
}
```

- [ ] **Step 2: Run and watch it fail** — `cannot find 'Difficulty' in scope`.

- [ ] **Step 3: Add the taxonomy**

In `Taxonomies.swift`, following the exact shape of the neighbouring types:

```swift
/// Roughly how much training experience a movement asks for.
///
/// Used to match exercise selection to the lifter's stated experience so a
/// beginner is not handed a snatch. Derived from mechanic and equipment when
/// the source data does not state it. Depends on: `ExtensibleTaxonomy`.
struct Difficulty: ExtensibleTaxonomy {
    let rawValue: String
    init(rawValue: String) { self.rawValue = Self.canonicalized(rawValue) }

    static let beginner = Difficulty(rawValue: "beginner")
    static let intermediate = Difficulty(rawValue: "intermediate")
    static let advanced = Difficulty(rawValue: "advanced")

    static let known: [Difficulty] = [.beginner, .intermediate, .advanced]
}
```

- [ ] **Step 4: Add it to `Exercise`**

Add `let difficulty: Difficulty` with a default of `.intermediate` in the
memberwise initializer, and decode it with
`try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .intermediate`.
Defaulting rather than requiring keeps the lenient-decoding contract: an older
catalog without the field still loads.

- [ ] **Step 5: Add the derivation rules**

```json
"difficultyByPattern": { "olympic": "advanced", "plyometric": "advanced" },
"difficultyByEquipment": {
  "machine": "beginner", "cable": "beginner", "band": "beginner",
  "cardio machine": "beginner"
},
"difficultyByMechanic": { "compound": "intermediate", "isolation": "beginner" },
"defaultDifficulty": "intermediate"
```

In `build-catalog.py`, resolve in this precedence: pattern, then equipment, then
mechanic, then the default. free-exercise-db's `level` field — which exists in
the source and has never been imported — wins over all of them where an entry is
enriched, mapping `expert` to `advanced`.

- [ ] **Step 6: Regenerate, inspect the distribution, and run the tests**

```sh
python3 Tools/build-catalog.py --fedb /private/tmp/claude-501/-Users-jonluon-jonluongo/d714977f-a666-4255-994f-8d8f38cc2b32/scratchpad/fedb.json
python3 -c "
import json, collections
c = json.load(open('LiftingPlan/Catalog/Resources/exercises.json'))
print(collections.Counter(e['difficulty'] for e in c))
"
```

A sane distribution has all three levels represented and is not overwhelmingly
one value. If it is, the precedence is wrong — report the distribution.

- [ ] **Step 7: Commit**

```sh
git add Tools LiftingPlan/Domain LiftingPlan/Catalog/Resources/exercises.json LiftingPlanTests
git commit -m "Add exercise difficulty derived from pattern, equipment, and mechanic"
```

---

### Task 3: Lifter data

Closes the gap that stops a first plan from suggesting any weight.

**Files:**
- Create: `LiftingPlan/Store/BodyMetric.swift`, `LiftingPlan/Store/StrengthBaseline.swift`
- Modify: `LiftingPlan/Store/UserProfile.swift`, `LiftingPlan/Store/StoreContainer.swift`
- Test: `LiftingPlanTests/LifterDataTests.swift`

**Interfaces:**
- Consumes: `Mass`, `ExerciseID`, `MovementPattern`.
- Produces: `BodyMetric`, `StrengthBaseline`; `UserProfile.bodyweight`, `.avoidedPatterns`, `.avoidedExercises`, `.permits(_:)`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftData
import Foundation
@testable import LiftingPlan

@Suite("Lifter data")
struct LifterDataTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    @Test("Bodyweight is a tracked series, not one mutable number")
    func bodyweightIsASeries() throws {
        let context = try context()
        context.insert(BodyMetric(date: .distantPast, bodyweight: Mass(value: 180, unit: .pounds)))
        context.insert(BodyMetric(date: .distantFuture, bodyweight: Mass(value: 185, unit: .pounds)))
        try context.saveOrThrow()

        let metrics = try context.fetch(FetchDescriptor<BodyMetric>()).sorted { $0.date < $1.date }
        #expect(metrics.count == 2)
        #expect(metrics.first?.bodyweight?.value == 180)
        #expect(metrics.last?.bodyweight?.value == 185)
    }

    @Test("A strength baseline records what the lifter can currently do")
    func baselineRecordsCurrentStrength() throws {
        let context = try context()
        context.insert(StrengthBaseline(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            load: Mass(value: 185, unit: .pounds), reps: 5
        ))
        try context.saveOrThrow()

        let baseline = try #require(try context.fetch(FetchDescriptor<StrengthBaseline>()).first)
        #expect(baseline.exerciseID == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(baseline.load?.value == 185)
        #expect(baseline.reps == 5)
        // Comparable across units, like everything else that reasons about load.
        #expect((baseline.estimatedOneRepMaxKilograms ?? 0) > 0)
    }

    @Test("An avoided pattern makes a constraint enforceable rather than advisory")
    func avoidedPatternsFilter() throws {
        let context = try context()
        let profile = UserProfile()
        profile.avoidedPatterns = [.verticalPress]
        context.insert(profile)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(!loaded.permits(pattern: .verticalPress))
        #expect(loaded.permits(pattern: .squat))
    }

    @Test("An avoided exercise is excluded by id")
    func avoidedExercisesFilter() throws {
        let context = try context()
        let profile = UserProfile()
        profile.avoidedExercises = [ExerciseID(rawValue: "barbell-bench-press")]
        context.insert(profile)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(!loaded.permits(exercise: ExerciseID(rawValue: "barbell-bench-press")))
        #expect(loaded.permits(exercise: ExerciseID(rawValue: "push-up")))
    }

    @Test("The new models satisfy CloudKit's defaulted-property requirement")
    func cloudKitCompatible() throws {
        let context = try context()
        context.insert(BodyMetric())
        context.insert(StrengthBaseline())
        try context.saveOrThrow()
    }
}
```

- [ ] **Step 2: Run and watch it fail** — `cannot find 'BodyMetric' in scope`.

- [ ] **Step 3: Write the two models**

Follow the doc-comment and defaulted-property conventions of the existing
`Store/` models exactly — read `LoggedSet.swift` first. Both need every property
optional or defaulted. `StrengthBaseline` carries `exerciseID`, `load: Mass?`,
`reps: Int`, `recordedAt: Date`, and an `estimatedOneRepMaxKilograms` computed
the same way `LoggedSet` does it, so the two agree.

- [ ] **Step 4: Extend `UserProfile`**

Add `bodyweight: Mass?`, plus `avoidedPatterns` and `avoidedExercises` stored as
raw-value arrays with computed accessors — the same pattern
`TrainingPlan.weekdays` already uses. Add:

```swift
/// Whether this lifter's constraints allow the movement pattern.
func permits(pattern: MovementPattern) -> Bool { !avoidedPatterns.contains(pattern) }

/// Whether this lifter's constraints allow the specific exercise.
func permits(exercise id: ExerciseID) -> Bool { !avoidedExercises.contains(id) }
```

Free-text `constraints` stays — it carries nuance the model reads that a list
cannot express.

- [ ] **Step 5: Register both models in `StoreContainer.schema`**

A model missing from the schema silently never persists.

- [ ] **Step 6: Run the full suite and commit**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test run with|✘|error:"
git add LiftingPlan/Store LiftingPlanTests/LifterDataTests.swift
git commit -m "Record bodyweight, strength baselines, and enforceable constraints"
```

Report the count. Expect roughly 113 — 102 plus the new tests.

---

## What this plan does not cover

- **Collecting the data.** The chat asks for bodyweight and current lifts
  conversationally; that belongs with the chat shell.
- **Consuming it.** Plan generation is the next plan.
- **Instructions coverage** stays at 18% — deliberate, per the spec.
