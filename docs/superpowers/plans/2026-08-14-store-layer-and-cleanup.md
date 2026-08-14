# Store Layer and Legacy Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the user-data models with a CloudKit-ready store built on the
Domain layer — carrying units, stable exercise identity, and the five-level
plan/week/day/exercise/set hierarchy — and delete the legacy code those changes
make obsolete.

**Revised 2026-08-14** per `docs/superpowers/specs/2026-08-14-app-structure-revision.md`:
a plan is now a multi-week block rather than a single week, and plans own a
conversation thread. Task 4 below reflects that; earlier tasks are unchanged.

**Architecture:** A new `Store/` layer holds SwiftData models written to
CloudKit's constraints. Every weight becomes a `Mass`; every exercise reference
becomes an `ExerciseID` plus a denormalized display name. The old models are
deleted rather than migrated — the app is pre-release and a clean schema is
worth more than its test data.

**Tech Stack:** Swift 6, SwiftData with CloudKit, Swift Testing, SwiftUI.

## Global Constraints

Copied verbatim from `CLAUDE.md` and
`docs/superpowers/specs/2026-08-14-foundation-architecture-design.md`.

- A layer may import only the layers above it. `Domain/` imports Foundation only; `Catalog/` imports Domain; `Store/` imports Domain; `Services/` imports Domain, Catalog, Store; `Views/` imports all.
- Errors are handled or propagated, never discarded. No `try?` that drops an error.
- No force unwrapping, force try, or force casting outside tests.
- Data over code. No numeric literal expressing a training opinion inside a function body.
- Extensible taxonomies, not closed enums. Unknown values round-trip intact.
- Protocol seams at boundaries.
- Tests before implementation.
- Every public type's doc comment answers: what it does, how it is used, what it depends on.
- Warnings are errors. Swift 6 language mode, strict concurrency.
- Files stay focused. Past roughly 300 lines is a signal it is doing too much.
- **CloudKit constraints, which shape every model in this plan:** every property is optional or has a default value; no `@Attribute(.unique)`; every relationship is optional and has an inverse.

**Build and test command** (used in every verification step):

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 \
  | grep -E "Test run with|✘|error:"
```

**Reading test output — this project has a trap.** `xcodebuild` prints
`Test Suite 'All tests' passed. Executed 0 tests` from the legacy XCTest
reporter. That is expected; every test here is Swift Testing. `** TEST
SUCCEEDED **` alone does *not* prove tests ran. The proof is
`✔ Test run with N tests in M suites passed`. Always confirm the count.

**Adding files:** the Xcode project uses `PBXFileSystemSynchronizedRootGroup`.
Creating a file under `LiftingPlan/` adds it to the target automatically. Never
hand-edit `project.pbxproj`. If `xcodebuild` rewrites it (objectVersion 77 → 71),
revert with `git checkout --` before committing — toolchain noise.

**Starting state:** 71 tests in 10 suites passing.

---

## The deletion inventory

Surveyed against the live codebase, not assumed. Everything here is deleted or
rewritten by this plan; nothing is left orphaned.

| What | Where | Why it goes |
|---|---|---|
| `movementCatalog(for:equipment:)` and `struct Movement` | `Services/TemplatePlanBuilder.swift:88-169` | The hardcoded 37-name exercise list. Superseded by the 412-entry catalog. This is the single biggest data-over-code violation in the repo. |
| `weight: Double?` | `Models/SetLog.swift:12` | Unitless. Replaced by a stored value plus `MassUnit`. |
| `name`/`muscleGroup` as identity | `Models/PlannedExercise.swift:7-8` | Free-text identity. Replaced by `exerciseID` plus a denormalized display name. |
| Name-keyed history matching | `Services/PerformanceHistory.swift:19,35-38` | `exercise.name.lowercased()` as a join key is what fragments history. Re-keyed to `ExerciseID`. |
| `TrainingPreferences` | `Models/TrainingPreferences.swift` (whole file) | Mixes identity with scheduling. Identity moves to `UserProfile`; training days and duration become properties of a `TrainingPlan`, since different blocks may train different days. |
| Nine `try? context.save()` | `Views/ActiveWorkoutView.swift` (5), `Views/RootView.swift`, `Views/SettingsView.swift`, `Views/SetupView.swift`, `Services/PlanCoordinator.swift` | Every persistence write silently discards failures. With CloudKit, save conflicts are expected rather than exceptional. |

**Kept, with reasoning** — so a future reader does not delete them by mistake:

- `Weekday` (`Models/Enums.swift`) — still the scheduling primitive.
- `ExperienceLevel` — still shapes volume and `PlanGenerator`'s prompt.
- `Equipment` — **not** redundant with `EquipmentType`. `Equipment` is the
  lifter's *access tier* ("dumbbells only"); `EquipmentType` is a *per-exercise
  requirement* ("this needs a barbell"). Task 3 adds the mapping between them
  rather than deleting either.
- `ProgressionEngine`, `RestTimerModel`, `PlanBlueprint` — pure and still
  correct; they change only where `Mass` replaces `Double`.

**Not in this plan, deliberately:** rewriting `TemplatePlanBuilder`'s selection
logic against the catalog, routing `PlanGenerator` output through
`ExerciseResolver`, and the programming rules from
`2026-08-14-workout-programming-design.md`. Those are the Services plan that
follows. This plan only deletes the hardcoded catalog and leaves
`TemplatePlanBuilder` returning an explicitly empty result, so the Services plan
has a clean seam to build on.

---

## File Structure

| File | Responsibility |
|---|---|
| `LiftingPlan/Domain/EquipmentAccess.swift` | Maps a lifter's access tier onto the set of `EquipmentType` values it permits. Pure. |
| `LiftingPlan/Store/UserProfile.swift` | Who the lifter is: display unit, experience, equipment access, constraints, goal. |
| `LiftingPlan/Store/TrainingPlan.swift` | A training block: goal, start date, week count, status, training days. Owns weeks and messages. |
| `LiftingPlan/Store/TrainingWeek.swift` | One week within a block. Carries a label and `isDeload`. Owns days. |
| `LiftingPlan/Store/WorkoutDay.swift` | One training day. Owns planned exercises. |
| `LiftingPlan/Store/PlanMessage.swift` | One conversational turn scoped to a plan — what makes a plan project-like. |
| `LiftingPlan/Store/PlannedExercise.swift` | A prescribed movement, keyed by `ExerciseID`. Owns logged sets. |
| `LiftingPlan/Store/LoggedSet.swift` | One set: a `Mass` as entered, reps, RPE, completion. |
| `LiftingPlan/Store/StoreContainer.swift` | Builds the `ModelContainer`, CloudKit-backed or in-memory for tests. |
| `LiftingPlan/Store/PersistenceError.swift` | The error surfaced when a save fails, replacing `try?`. |
| `LiftingPlanTests/EquipmentAccessTests.swift` | Access-tier → equipment-type mapping. |
| `LiftingPlanTests/StoreModelTests.swift` | Round-trips, the plan/week/day/exercise/set hierarchy, cascade deletes, unit fidelity, CloudKit defaults. |
| `LiftingPlanTests/PersistenceErrorTests.swift` | A failed save surfaces rather than vanishing. |

Deleted outright: `Models/TrainingPreferences.swift`, `Models/WorkoutPlan.swift`,
`Models/WorkoutSession.swift`, `Models/PlannedExercise.swift`,
`Models/SetLog.swift`. `Models/Enums.swift` survives and moves to `Domain/`.

---

### Task 1: Move `Enums.swift` into Domain and prove the layer boundary

`Weekday`, `Equipment`, and `ExperienceLevel` are pure value types with no
persistence or UI dependency, but they sit in `Models/` where the SwiftData
types live. Moving them first means every later task imports them from the
right layer.

**Files:**
- Create: `LiftingPlan/Domain/TrainingEnums.swift` (content moved verbatim from `Models/Enums.swift`)
- Delete: `LiftingPlan/Models/Enums.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Weekday`, `Equipment`, `ExperienceLevel` at their new location. Every later task and every existing view depends on them.

- [ ] **Step 1: Confirm the starting baseline**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: `✔ Test run with 71 tests in 10 suites passed`. If it is anything
else, stop and report — do not build on a broken baseline.

- [ ] **Step 2: Move the file**

```sh
git mv LiftingPlan/Models/Enums.swift LiftingPlan/Domain/TrainingEnums.swift
```

Do not edit the contents. These three types are unchanged by this plan.

- [ ] **Step 3: Verify nothing broke**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: `✔ Test run with 71 tests in 10 suites passed`. Swift has no
file-level imports within a module, so a pure move compiles unchanged. If it
does not, something in those types referenced SwiftData — report it rather than
working around it.

- [ ] **Step 4: Commit**

```sh
git add -A LiftingPlan
git commit -m "Move training enums into the Domain layer"
```

---

### Task 2: `EquipmentAccess` — map access tier to equipment types

The lifter says "dumbbells only"; the catalog says an exercise needs
`EquipmentType.barbell`. Something has to relate the two, and it is pure logic,
so it belongs in Domain and gets tested without a database.

**Files:**
- Create: `LiftingPlan/Domain/EquipmentAccess.swift`
- Test: `LiftingPlanTests/EquipmentAccessTests.swift`

**Interfaces:**
- Consumes: `Equipment` (Task 1), `EquipmentType`.
- Produces: `enum EquipmentAccess` with `static func permitted(for: Equipment) -> Set<EquipmentType>`. Used by the Services plan to filter the catalog.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import LiftingPlan

@Suite("Equipment access")
struct EquipmentAccessTests {

    @Test("Bodyweight access permits only bodyweight movements")
    func bodyweightOnly() {
        #expect(EquipmentAccess.permitted(for: .bodyweight) == [.bodyweight])
    }

    @Test("Every tier permits bodyweight, because you can always do a push-up")
    func bodyweightAlwaysAvailable() {
        for tier in Equipment.allCases {
            #expect(EquipmentAccess.permitted(for: tier).contains(.bodyweight),
                    "\(tier) should permit bodyweight")
        }
    }

    @Test("A full gym permits barbell, machine, and cable work")
    func fullGym() {
        let permitted = EquipmentAccess.permitted(for: .fullGym)
        #expect(permitted.contains(.barbell))
        #expect(permitted.contains(.machine))
        #expect(permitted.contains(.cable))
    }

    @Test("Dumbbells-only excludes barbell, machine, and cable")
    func dumbbellsOnly() {
        let permitted = EquipmentAccess.permitted(for: .dumbbellsOnly)
        #expect(permitted.contains(.dumbbell))
        #expect(!permitted.contains(.barbell))
        #expect(!permitted.contains(.machine))
        #expect(!permitted.contains(.cable))
    }

    @Test("A minimal home setup permits bands but not machines")
    func homeMinimal() {
        let permitted = EquipmentAccess.permitted(for: .homeMinimal)
        #expect(permitted.contains(.band))
        #expect(permitted.contains(.dumbbell))
        #expect(!permitted.contains(.machine))
    }

    @Test("Access tiers widen monotonically from bodyweight to full gym")
    func tiersNest() {
        let bodyweight = EquipmentAccess.permitted(for: .bodyweight)
        let home = EquipmentAccess.permitted(for: .homeMinimal)
        let gym = EquipmentAccess.permitted(for: .fullGym)
        #expect(bodyweight.isSubset(of: home))
        #expect(home.isSubset(of: gym))
    }

    @Test("Every permitted type is one the catalog actually uses")
    func permittedTypesAreReal() throws {
        let catalog = try ExerciseCatalog.bundled()
        let inCatalog = Set(catalog.all.map(\.equipment))
        for tier in Equipment.allCases {
            for type in EquipmentAccess.permitted(for: tier) {
                #expect(inCatalog.contains(type),
                        "\(tier) permits \(type), which no catalog exercise uses")
            }
        }
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LiftingPlanTests/EquipmentAccessTests test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: compile failure — `cannot find 'EquipmentAccess' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Maps the lifter's stated equipment access onto the concrete
/// `EquipmentType` values a catalog exercise may require.
///
/// The lifter answers a coarse question ("dumbbells only"); the catalog states
/// a precise requirement ("this needs a barbell"). Use this to turn the former
/// into a filter over the latter. Tiers widen monotonically — everything a
/// minimal home setup allows, a full gym allows too — and every tier includes
/// bodyweight, because a push-up needs nothing.
///
/// Depends on: `Equipment` and `EquipmentType`. No persistence, no UI.
enum EquipmentAccess {

    /// The equipment types a lifter at this access tier can actually use.
    static func permitted(for access: Equipment) -> Set<EquipmentType> {
        switch access {
        case .bodyweight:
            bodyweightTier
        case .homeMinimal:
            homeTier
        case .dumbbellsOnly:
            dumbbellTier
        case .fullGym:
            gymTier
        }
    }

    private static let bodyweightTier: Set<EquipmentType> = [.bodyweight]

    private static let dumbbellTier: Set<EquipmentType> =
        bodyweightTier.union([.dumbbell, .plate])

    private static let homeTier: Set<EquipmentType> =
        dumbbellTier.union([.band, .kettlebell, .suspension, .medicineBall])

    private static let gymTier: Set<EquipmentType> =
        homeTier.union([
            .barbell, .machine, .cable, .ezBar, .trapBar,
            .sled, .cardioMachine, .other,
        ])
}
```

- [ ] **Step 4: Run the tests**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LiftingPlanTests/EquipmentAccessTests test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: `✔ Test run with 7 tests in 1 suite passed`.

If `permittedTypesAreReal` fails, a tier permits a type no catalog exercise
uses. Fix the tier — do not weaken the test. If `tiersNest` fails, a tier is
not built by `union`ing the one below it; restore that structure, because it is
what makes the monotonicity guarantee real rather than coincidental.

- [ ] **Step 5: Commit**

```sh
git add LiftingPlan/Domain/EquipmentAccess.swift LiftingPlanTests/EquipmentAccessTests.swift
git commit -m "Map equipment access tiers onto catalog equipment types"
```

---

### Task 3: `PersistenceError` and a save helper that cannot be ignored

Nine call sites currently write `try? context.save()`. The fix is not to
sprinkle `do/catch` — it is to make the ignoring shape unavailable and give
callers one helper that either succeeds or throws something presentable.

**Files:**
- Create: `LiftingPlan/Store/PersistenceError.swift`
- Test: `LiftingPlanTests/PersistenceErrorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum PersistenceError: Error, LocalizedError` with case `saveFailed(underlying: any Error)`; `extension ModelContext { func saveOrThrow() throws }`. Used by every write in Tasks 4–7.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftData
import Foundation
@testable import LiftingPlan

@Suite("Persistence errors")
struct PersistenceErrorTests {

    @Test("A persistence error carries a message a user could be shown")
    func hasUserFacingDescription() {
        struct Underlying: Error {}
        let error = PersistenceError.saveFailed(underlying: Underlying())
        let description = error.errorDescription
        #expect(description != nil)
        #expect(!(description ?? "").isEmpty)
    }

    @Test("A persistence error keeps the underlying cause for diagnosis")
    func preservesUnderlyingError() {
        struct Underlying: Error, Equatable { let code = 42 }
        let error = PersistenceError.saveFailed(underlying: Underlying())
        guard case .saveFailed(let underlying) = error else {
            Issue.record("expected saveFailed")
            return
        }
        #expect(underlying is Underlying)
    }

    @Test("Saving a valid context succeeds")
    func saveSucceeds() throws {
        let container = try StoreContainer.inMemory()
        let context = ModelContext(container)
        context.insert(UserProfile())
        try context.saveOrThrow()
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LiftingPlanTests/PersistenceErrorTests test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: compile failure — `cannot find 'PersistenceError' in scope`. It will
also fail on `StoreContainer` and `UserProfile`, which Task 4 creates; that is
expected, and this suite goes green at the end of Task 4.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import SwiftData

/// A failure while writing to the store.
///
/// Catch this at the UI boundary and show `errorDescription` — every write in
/// this app can fail, and with CloudKit sync a conflict is an expected
/// outcome rather than an exceptional one. Depends on: Foundation and
/// SwiftData.
enum PersistenceError: Error, LocalizedError {
    case saveFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            "Your changes could not be saved. Check your connection and try again."
        }
    }

    /// The original error, for logging and diagnosis. Never shown to the user.
    var underlyingError: any Error {
        switch self {
        case .saveFailed(let underlying): underlying
        }
    }
}

extension ModelContext {

    /// Saves pending changes, wrapping any failure in a `PersistenceError`.
    ///
    /// Use this instead of `try? save()`. The whole point is that the failure
    /// cannot be discarded silently: a dropped save means a lifter's logged
    /// set disappears with no indication anything went wrong.
    func saveOrThrow() throws {
        do {
            try save()
        } catch {
            throw PersistenceError.saveFailed(underlying: error)
        }
    }
}
```

- [ ] **Step 4: Note the expected state**

This suite cannot pass until Task 4 provides `StoreContainer` and `UserProfile`.
Do not stub them here — implement them properly in Task 4 and let this suite go
green then. Commit the implementation now so the next task builds on it.

- [ ] **Step 5: Commit**

```sh
git add LiftingPlan/Store/PersistenceError.swift LiftingPlanTests/PersistenceErrorTests.swift
git commit -m "Add PersistenceError so failed saves cannot be discarded"
```

---

### Task 4: The store models

Replaces all five files under `Models/`, and builds the five-level hierarchy
from `2026-08-14-app-structure-revision.md`. Written to CloudKit's constraints
from the start: every property optional or defaulted, no unique attributes,
every relationship optional with an inverse.

The shape being built:

```
TrainingPlan  (a block: goal, start date, week count, status, training days)
  ├── TrainingWeek   (ordinal; may be a deload)
  │     └── WorkoutDay   (weekday, focus)
  │           └── PlannedExercise   (exerciseID + prescription)
  │                 └── LoggedSet   (what actually happened)
  └── PlanMessage    (the conversation scoped to this plan)
```

**Files:**
- Create: `LiftingPlan/Store/UserProfile.swift`, `TrainingPlan.swift`, `TrainingWeek.swift`, `WorkoutDay.swift`, `PlannedExercise.swift`, `LoggedSet.swift`, `PlanMessage.swift`, `StoreContainer.swift`
- Delete: `LiftingPlan/Models/TrainingPreferences.swift`, `WorkoutPlan.swift`, `WorkoutSession.swift`, `PlannedExercise.swift`, `SetLog.swift`
- Test: `LiftingPlanTests/StoreModelTests.swift`

**Interfaces:**
- Consumes: `Mass`, `MassUnit`, `ExerciseID` (Domain); `Equipment`, `ExperienceLevel`, `Weekday` (Task 1); `saveOrThrow` (Task 3).
- Produces: the seven `@Model` types above; `enum StoreContainer` with `static func inMemory() throws -> ModelContainer` and `static func cloudKit() throws -> ModelContainer`. Consumed by Tasks 5–7.

**Implement one model at a time**, bottom-up in the order given — each compiles
against the ones before it.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftData
import Foundation
@testable import LiftingPlan

@Suite("Store models")
struct StoreModelTests {

    private func context() throws -> ModelContext {
        ModelContext(try StoreContainer.inMemory())
    }

    @Test("A logged set stores the weight in the unit it was entered")
    func setKeepsEnteredUnit() throws {
        let context = try context()
        context.insert(LoggedSet(setIndex: 0, load: Mass(value: 135, unit: .pounds), reps: 5))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<LoggedSet>()).first)
        #expect(loaded.load?.value == 135)
        #expect(loaded.load?.unit == .pounds)
    }

    @Test("A bodyweight set has no load rather than a zero load")
    func bodyweightSetHasNoLoad() throws {
        let context = try context()
        context.insert(LoggedSet(setIndex: 0, load: nil, reps: 12))
        try context.saveOrThrow()
        #expect(try #require(try context.fetch(FetchDescriptor<LoggedSet>()).first).load == nil)
    }

    @Test("A planned exercise is keyed by exercise id, not by name")
    func plannedExerciseKeyedByID() throws {
        let context = try context()
        context.insert(PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press",
            order: 0, targetSets: 3, repRange: "5", restSeconds: 120
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<PlannedExercise>()).first)
        #expect(loaded.exerciseID == ExerciseID(rawValue: "barbell-bench-press"))
        #expect(loaded.displayName == "Barbell Bench Press")
    }

    @Test("A plan holds weeks in order, and a week can be a deload")
    func planHoldsOrderedWeeks() throws {
        let context = try context()
        let plan = TrainingPlan(title: "Strength block", goal: "Bigger bench", weekCount: 4)
        plan.weeks = [
            TrainingWeek(ordinal: 4, label: "Deload", isDeload: true),
            TrainingWeek(ordinal: 1, label: "Accumulation"),
        ]
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.orderedWeeks.map(\.ordinal) == [1, 4])
        #expect(loaded.orderedWeeks.last?.isDeload == true)
        #expect(loaded.orderedWeeks.first?.isDeload == false)
    }

    @Test("Weeks in one plan can prescribe different work — the point of the week layer")
    func weeksCanDiffer() throws {
        let context = try context()
        let heavy = TrainingWeek(ordinal: 1)
        heavy.days = [dayWithBench(sets: 5)]
        let deload = TrainingWeek(ordinal: 2, label: "Deload", isDeload: true)
        deload.days = [dayWithBench(sets: 2)]
        let plan = TrainingPlan(title: "Block", weekCount: 2)
        plan.weeks = [heavy, deload]
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        let setCounts = loaded.orderedWeeks.map { $0.orderedDays.first?.orderedExercises.first?.targetSets }
        #expect(setCounts == [5, 2])
    }

    private func dayWithBench(sets: Int) -> WorkoutDay {
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "barbell-bench-press"),
            displayName: "Barbell Bench Press",
            order: 0, targetSets: sets, repRange: "5", restSeconds: 180
        )
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        day.exercises = [exercise]
        return day
    }

    @Test("Deleting a plan cascades all the way down to logged sets")
    func cascadeDelete() throws {
        let context = try context()
        let exercise = PlannedExercise(
            exerciseID: ExerciseID(rawValue: "push-up"), displayName: "Push Up",
            order: 0, targetSets: 3, repRange: "10", restSeconds: 60
        )
        exercise.loggedSets = [LoggedSet(setIndex: 0, load: nil, reps: 10)]
        let day = WorkoutDay(weekday: .monday, focus: "Push")
        day.exercises = [exercise]
        let week = TrainingWeek(ordinal: 1)
        week.days = [day]
        let plan = TrainingPlan(title: "Block", weekCount: 1)
        plan.weeks = [week]
        context.insert(plan)
        try context.saveOrThrow()

        context.delete(plan)
        try context.saveOrThrow()

        #expect(try context.fetch(FetchDescriptor<TrainingWeek>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkoutDay>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlannedExercise>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<LoggedSet>()).isEmpty)
    }

    @Test("A plan owns its conversation, which is what makes it project-like")
    func planOwnsConversation() throws {
        let context = try context()
        let plan = TrainingPlan(title: "Block", weekCount: 8)
        plan.messages = [
            PlanMessage(role: .assistant, text: "Built you an 8-week block.", createdAt: .distantPast),
            PlanMessage(role: .user, text: "Make week 4 a deload", createdAt: .distantFuture),
        ]
        context.insert(plan)
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.orderedMessages.map(\.role) == [.assistant, .user])
        #expect(loaded.orderedMessages.first?.text.contains("8-week") == true)
    }

    @Test("A plan records its training days and its length")
    func planRecordsScheduleAndLength() throws {
        let context = try context()
        context.insert(TrainingPlan(
            title: "Block", goal: "Squat", weekCount: 12,
            weekdays: [.friday, .monday]
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<TrainingPlan>()).first)
        #expect(loaded.weekCount == 12)
        // `weekdays` is a Set, so compare against a Set — an array literal
        // here does not type-check.
        #expect(loaded.weekdays == Set<Weekday>([.monday, .friday]))
        #expect(loaded.orderedWeekdays == [.monday, .friday])
    }

    @Test("A profile round-trips its display unit and access tier")
    func profileRoundTrips() throws {
        let context = try context()
        context.insert(UserProfile(
            displayUnit: .kilograms, experience: .advanced,
            equipmentAccess: .dumbbellsOnly, goal: "Bigger bench"
        ))
        try context.saveOrThrow()

        let loaded = try #require(try context.fetch(FetchDescriptor<UserProfile>()).first)
        #expect(loaded.displayUnit == .kilograms)
        #expect(loaded.experience == .advanced)
        #expect(loaded.equipmentAccess == .dumbbellsOnly)
        #expect(loaded.permittedEquipment.contains(.dumbbell))
        #expect(!loaded.permittedEquipment.contains(.barbell))
    }

    @Test("Every model property is optional or defaulted, as CloudKit requires")
    func cloudKitCompatible() throws {
        // Constructing each model with no arguments proves every property
        // carries a default — the CloudKit requirement that is easiest to
        // violate accidentally and hardest to notice until sync fails.
        let context = try context()
        context.insert(UserProfile())
        context.insert(TrainingPlan())
        context.insert(TrainingWeek())
        context.insert(WorkoutDay())
        context.insert(PlannedExercise())
        context.insert(LoggedSet())
        context.insert(PlanMessage())
        try context.saveOrThrow()
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LiftingPlanTests/StoreModelTests test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: compile failure — `cannot find 'StoreContainer' in scope`.

- [ ] **Step 3: Write `LoggedSet`**

`Mass` is a `Codable` struct, so SwiftData persists it as a composite value —
no manual splitting into two columns.

```swift
import Foundation
import SwiftData

/// One set of one exercise, as the lifter logged it.
///
/// A row exists as soon as it is on screen, so `isCompleted` — not existence —
/// marks work as done, and checking it is what starts the rest timer. `load`
/// is `nil` for bodyweight movements rather than zero, so "no external weight"
/// and "an empty bar" stay distinguishable.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `Mass` from Domain.
@Model
final class LoggedSet {
    var setIndex: Int = 0
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    var load: Mass?
    var reps: Int = 0
    /// Rating of perceived exertion, 1–10.
    var rpe: Double?
    var isCompleted: Bool = false
    /// Warmup sets show as "W" and are excluded from progression math.
    var isWarmup: Bool = false
    var completedAt: Date = Date()

    var exercise: PlannedExercise?

    init(
        setIndex: Int = 0, load: Mass? = nil, reps: Int = 0, rpe: Double? = nil,
        isCompleted: Bool = false, isWarmup: Bool = false, completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.load = load
        self.reps = reps
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }

    /// A completed working set — the kind progression counts.
    var countsForProgression: Bool { isCompleted && !isWarmup }

    /// Estimated one-rep max via the Epley formula, in kilograms so values
    /// stay comparable across sets logged in different units.
    var estimatedOneRepMaxKilograms: Double? {
        guard let load, load.kilograms > 0, reps > 0 else { return nil }
        return load.kilograms * (1.0 + Double(reps) / 30.0)
    }
}
```

- [ ] **Step 4: Write `PlannedExercise`**

```swift
import Foundation
import SwiftData

/// A prescribed movement within a day, plus the sets logged against it.
///
/// `exerciseID` is the join key and the only identity that matters;
/// `displayName` is a denormalized copy kept so history stays readable if an
/// exercise is later renamed or dropped from the catalog. Never match on the
/// name — that is the bug this field replaced.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `ExerciseID` and `Mass` from Domain.
@Model
final class PlannedExercise {
    /// The catalog key. Resolve it through `ExerciseCatalog` for full details.
    var exerciseID: ExerciseID = ExerciseID(rawValue: "")
    /// Denormalized for display; never used as an identity or a join key.
    var displayName: String = ""
    var order: Int = 0
    var targetSets: Int = 0
    /// Human-readable rep target, e.g. "8-12" or "5".
    var repRange: String = ""
    var suggestedLoad: Mass?
    /// Rest between sets, in seconds — drives the pace timer.
    var restSeconds: Int = 90
    /// Optional rep tempo like "3-0-1-0".
    var tempo: String?
    var notes: String?

    var day: WorkoutDay?

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.exercise)
    var loggedSets: [LoggedSet]? = []

    init(
        exerciseID: ExerciseID = ExerciseID(rawValue: ""), displayName: String = "",
        order: Int = 0, targetSets: Int = 0, repRange: String = "",
        suggestedLoad: Mass? = nil, restSeconds: Int = 90,
        tempo: String? = nil, notes: String? = nil
    ) {
        self.exerciseID = exerciseID
        self.displayName = displayName
        self.order = order
        self.targetSets = targetSets
        self.repRange = repRange
        self.suggestedLoad = suggestedLoad
        self.restSeconds = restSeconds
        self.tempo = tempo
        self.notes = notes
    }

    /// Sets that count toward progression, in logging order.
    var completedWorkingSets: [LoggedSet] {
        (loggedSets ?? []).filter(\.countsForProgression).sorted { $0.setIndex < $1.setIndex }
    }
}
```

- [ ] **Step 5: Write `WorkoutDay` and `TrainingWeek`**

```swift
import Foundation
import SwiftData

/// One training day within a week.
///
/// Read `orderedExercises` rather than `exercises` — SwiftData does not
/// guarantee relationship ordering, and compounds-first order matters.
///
/// Every property has a default, as CloudKit requires. Depends on: `Weekday`.
@Model
final class WorkoutDay {
    var weekdayRawValue: Int = Weekday.monday.rawValue
    /// Short label such as "Push" or "Lower Body".
    var focus: String = ""
    var durationMinutes: Int = 45
    var completedAt: Date?

    var week: TrainingWeek?

    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.day)
    var exercises: [PlannedExercise]? = []

    init(
        weekday: Weekday = .monday, focus: String = "",
        durationMinutes: Int = 45, completedAt: Date? = nil
    ) {
        self.weekdayRawValue = weekday.rawValue
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.completedAt = completedAt
    }

    var weekday: Weekday {
        get { Weekday(rawValue: weekdayRawValue) ?? .monday }
        set { weekdayRawValue = newValue.rawValue }
    }

    /// Exercises in prescribed order — compounds first.
    var orderedExercises: [PlannedExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }
}

/// One week within a training block.
///
/// Weeks are stored concretely and may differ from one another — that is the
/// whole reason this layer exists. A deload week prescribes genuinely less
/// work than the week before it, rather than the same work at a lower load.
///
/// Every property has a default, as CloudKit requires.
@Model
final class TrainingWeek {
    /// 1-based position within the plan.
    var ordinal: Int = 1
    /// Short label such as "Accumulation" or "Deload". May be empty.
    var label: String = ""
    var isDeload: Bool = false

    var plan: TrainingPlan?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutDay.week)
    var days: [WorkoutDay]? = []

    init(ordinal: Int = 1, label: String = "", isDeload: Bool = false) {
        self.ordinal = ordinal
        self.label = label
        self.isDeload = isDeload
    }

    /// Days in Monday-first display order.
    var orderedDays: [WorkoutDay] {
        (days ?? []).sorted {
            (Weekday.displayOrder.firstIndex(of: $0.weekday) ?? 0)
                < (Weekday.displayOrder.firstIndex(of: $1.weekday) ?? 0)
        }
    }
}
```

- [ ] **Step 6: Write `PlanMessage` and `TrainingPlan`**

```swift
import Foundation
import SwiftData

/// Who produced a turn in a plan's conversation.
enum PlanMessageRole: String, Codable, Sendable, CaseIterable {
    case user
    case assistant
}

/// One turn in the conversation attached to a plan.
///
/// This is what makes a plan project-like rather than a bare record: the
/// discussion that produced and revised it lives with it, so "make week 4 a
/// deload" is scoped to one plan instead of a global chat.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PlanMessage {
    private var roleRaw: String = PlanMessageRole.user.rawValue
    var text: String = ""
    var createdAt: Date = Date()

    var plan: TrainingPlan?

    init(role: PlanMessageRole = .user, text: String = "", createdAt: Date = Date()) {
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
    }

    var role: PlanMessageRole {
        get { PlanMessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }
}

/// A training block: a fixed-length program the lifter is working through.
///
/// This is the top of the user-data hierarchy and the unit the interface
/// treats as a project — it owns its weeks and its conversation. A plan is
/// finite by design, so finishing one is a real event the chat can respond to
/// by proposing the next block.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `Weekday`.
@Model
final class TrainingPlan {
    var title: String = ""
    var goal: String = ""
    var startDate: Date = Date()
    /// How many weeks the block runs. Typically 8–12.
    var weekCount: Int = 8
    var completedAt: Date?
    /// Whether the on-device model produced this plan or the template did.
    var wasModelGenerated: Bool = false
    /// Which days this block trains. Different blocks may train different days.
    private var weekdayRawValues: [Int] = [
        Weekday.monday.rawValue, Weekday.wednesday.rawValue, Weekday.friday.rawValue,
    ]
    var durationMinutes: Int = 45

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.plan)
    var weeks: [TrainingWeek]? = []

    @Relationship(deleteRule: .cascade, inverse: \PlanMessage.plan)
    var messages: [PlanMessage]? = []

    init(
        title: String = "", goal: String = "", startDate: Date = Date(),
        weekCount: Int = 8, weekdays: Set<Weekday> = [.monday, .wednesday, .friday],
        durationMinutes: Int = 45, wasModelGenerated: Bool = false
    ) {
        self.title = title
        self.goal = goal
        self.startDate = startDate
        self.weekCount = weekCount
        self.weekdayRawValues = weekdays.map(\.rawValue).sorted()
        self.durationMinutes = durationMinutes
        self.wasModelGenerated = wasModelGenerated
    }

    var weekdays: Set<Weekday> {
        get { Set(weekdayRawValues.compactMap(Weekday.init(rawValue:))) }
        set { weekdayRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// Training days in Monday-first display order.
    var orderedWeekdays: [Weekday] {
        Weekday.displayOrder.filter { weekdays.contains($0) }
    }

    /// Weeks in program order.
    var orderedWeeks: [TrainingWeek] {
        (weeks ?? []).sorted { $0.ordinal < $1.ordinal }
    }

    /// Conversation in chronological order.
    var orderedMessages: [PlanMessage] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var isComplete: Bool { completedAt != nil }
}
```

- [ ] **Step 7: Write `UserProfile`**

`TrainingSchedule` from the earlier draft is gone — training days and duration
are properties of a plan now, since different blocks may train different days.

```swift
import Foundation
import SwiftData

/// Who the lifter is: the standing facts that shape every generated plan.
///
/// Exactly one instance is expected. CloudKit forbids unique constraints, so
/// that invariant is enforced in application code rather than by the schema.
/// `displayUnit` controls what new entries default to and how weights are
/// shown; it never rewrites what was already logged.
///
/// Every property has a default, as CloudKit requires.
@Model
final class UserProfile {
    private var displayUnitRaw: String = MassUnit.pounds.rawValue
    private var experienceRaw: String = ExperienceLevel.intermediate.rawValue
    private var equipmentAccessRaw: String = Equipment.fullGym.rawValue
    var goal: String = ""
    /// Injuries and constraints, in the lifter's own words. Fed to the model.
    var constraints: String = ""
    var hasCompletedSetup: Bool = false
    var updatedAt: Date = Date()

    init(
        displayUnit: MassUnit = .pounds,
        experience: ExperienceLevel = .intermediate,
        equipmentAccess: Equipment = .fullGym,
        goal: String = "", constraints: String = "", hasCompletedSetup: Bool = false
    ) {
        self.displayUnitRaw = displayUnit.rawValue
        self.experienceRaw = experience.rawValue
        self.equipmentAccessRaw = equipmentAccess.rawValue
        self.goal = goal
        self.constraints = constraints
        self.hasCompletedSetup = hasCompletedSetup
        self.updatedAt = Date()
    }

    var displayUnit: MassUnit {
        get { MassUnit(rawValue: displayUnitRaw) ?? .pounds }
        set { displayUnitRaw = newValue.rawValue }
    }

    var experience: ExperienceLevel {
        get { ExperienceLevel(rawValue: experienceRaw) ?? .intermediate }
        set { experienceRaw = newValue.rawValue }
    }

    var equipmentAccess: Equipment {
        get { Equipment(rawValue: equipmentAccessRaw) ?? .fullGym }
        set { equipmentAccessRaw = newValue.rawValue }
    }

    /// The equipment types this lifter can actually train with.
    var permittedEquipment: Set<EquipmentType> {
        EquipmentAccess.permitted(for: equipmentAccess)
    }
}
```

- [ ] **Step 8: Write `StoreContainer`**

```swift
import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// Call `cloudKit()` from the app entry point and `inMemory()` from tests and
/// previews. Keeping both behind one type means the schema is declared once,
/// so a model added to the app but forgotten in tests cannot happen.
///
/// Depends on: the `Store/` models.
enum StoreContainer {

    /// Every persisted model. Adding a model without adding it here means it
    /// silently never persists.
    static let schema = Schema([
        UserProfile.self,
        TrainingPlan.self,
        TrainingWeek.self,
        WorkoutDay.self,
        PlannedExercise.self,
        LoggedSet.self,
        PlanMessage.self,
    ])

    /// The production container, backed by the user's private CloudKit database.
    static func cloudKit() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An ephemeral container for tests and previews. Never touches CloudKit.
    static func inMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

- [ ] **Step 9: Delete the old models**

```sh
git rm LiftingPlan/Models/TrainingPreferences.swift \
       LiftingPlan/Models/WorkoutPlan.swift \
       LiftingPlan/Models/WorkoutSession.swift \
       LiftingPlan/Models/PlannedExercise.swift \
       LiftingPlan/Models/SetLog.swift
```

The `Models/` directory should now be empty; remove it if git leaves it behind.
The build will break — every view and service references these types. Tasks 5
through 7 repair the call sites. Do not stub the old types to keep the build
green; a broken build here is the honest signal of how far the change reaches.

- [ ] **Step 10: Run the store tests**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:LiftingPlanTests/StoreModelTests test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: `✔ Test run with 10 tests in 1 suite passed`. The `Views/` targets do
not compile yet; confirm no error originates from `Store/` before moving on.

If `cloudKitCompatible` fails, a property lacks a default — that is the CloudKit
requirement that is easiest to miss and hardest to notice, because it surfaces
as a sync failure rather than a compile error. Fix the model, not the test.

- [ ] **Step 11: Commit**

```sh
git add -A LiftingPlan LiftingPlanTests
git commit -m "Replace user-data models with a CloudKit-ready plan hierarchy"
```

---

### Task 5: Repair `PlanBlueprint` and `PerformanceHistory`

These two are the service-layer bridge into the store. `PerformanceHistory` is
where the name-matching bug lived.

**Files:**
- Modify: `LiftingPlan/Services/PlanBlueprint.swift`, `LiftingPlan/Services/PerformanceHistory.swift`, `LiftingPlan/Services/ProgressionEngine.swift`
- Test: update `LiftingPlanTests/PlanMappingTests.swift`, `LiftingPlanTests/ProgressionEngineTests.swift`

**Interfaces:**
- Consumes: the Task 4 models; `Mass`, `ExerciseID`.
- Produces: `ExerciseHistory` keyed by `ExerciseID`; `PerformanceHistory.latestHistory(for:excluding:from:)` taking an `ExerciseID`.

- [ ] **Step 1: Re-key `ExerciseHistory` to `ExerciseID`**

In `ProgressionEngine.swift`, change `ExerciseHistory`'s `name: String` to
`exerciseID: ExerciseID` plus a `displayName: String` for message text, and
change `SetRecord`'s `weight: Double?` to `load: Mass?`. Progression math
compares `load?.kilograms` so sets logged in different units stay comparable.

- [ ] **Step 2: Re-key `PerformanceHistory`**

Replace every `exercise.name.lowercased()` with `exercise.exerciseID`. The
deduplication set becomes `Set<ExerciseID>`, and
`latestHistory(forExerciseNamed:)` becomes `latestHistory(for: ExerciseID)`.
**There must be no remaining string comparison of exercise names anywhere in
this file** — that is the whole point of the change. Verify with:

```sh
grep -n "name" LiftingPlan/Services/PerformanceHistory.swift
```

Expected: matches only on `displayName` being carried through for display, never
on a name used as a key or in a comparison.

- [ ] **Step 3: Repair `PlanBlueprint`**

`ExerciseBlueprint` gains `exerciseID: ExerciseID` alongside its display name,
and `suggestedWeight: Double?` becomes `suggestedLoad: Mass?`. Its
`makeWorkoutPlan` mapping constructs the Task 4 models.

- [ ] **Step 4: Update the affected tests**

`PlanMappingTests` and `ProgressionEngineTests` reference the old shapes.
Update them to the new types. **Do not weaken any assertion while updating** —
if a test now fails for a real reason, that is a finding, not a nuisance.

- [ ] **Step 5: Run the tests**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test run with|✘|error:"
```

The Views still do not compile; expect errors from `Views/`. Confirm no errors
originate from `Services/` or `Store/` before moving on.

- [ ] **Step 6: Commit**

```sh
git add LiftingPlan/Services LiftingPlanTests
git commit -m "Key performance history by exercise id instead of by name"
```

---

### Task 6: Empty out `TemplatePlanBuilder`

Deletes the hardcoded 37-name catalog. Rebuilding selection against the real
catalog belongs to the Services plan; this task only removes the old data and
leaves an honest seam.

**Files:**
- Modify: `LiftingPlan/Services/TemplatePlanBuilder.swift`
- Modify: `LiftingPlanTests/TemplatePlanBuilderTests.swift`

**Interfaces:**
- Produces: `TemplatePlanBuilder.splitTemplate(forDayCount:)` unchanged (it is real programming knowledge worth keeping); `build(...)` returning an empty `PlanBlueprint`, with a doc comment naming the Services plan as where selection gets rebuilt.

- [ ] **Step 1: Delete the hardcoded catalog**

Remove `movementCatalog(for:equipment:)`, `private struct Movement`, and the
`exercises(for:...)` helper that consumes them — roughly lines 57 through 169.
Keep `splitTemplate(forDayCount:)`: which split suits how many days a week is
genuine programming knowledge, not a hardcoded exercise list.

- [ ] **Step 2: Leave an honest seam**

```swift
/// Builds a week of training without the on-device model.
///
/// **Currently returns an empty plan.** The hardcoded exercise list this used
/// to carry was deleted with the arrival of the 412-entry catalog; selecting
/// from that catalog against the programming rules in
/// `docs/superpowers/specs/2026-08-14-workout-programming-design.md` is the
/// next plan's work. Returning empty is deliberate — a caller gets a visibly
/// empty plan rather than silently wrong exercises.
static func build(
    weekdays: [Weekday],
    durationMinutes: Int,
    equipment: Equipment,
    experience: ExperienceLevel
) -> PlanBlueprint {
    PlanBlueprint(days: [])
}
```

- [ ] **Step 3: Update the tests to assert the new contract**

Delete the tests asserting specific exercise names and equipment substitutions —
they tested the deleted data. Keep and keep passing the `splitTemplate` tests.
Add one test asserting `build` returns an empty plan, so the seam is documented
in code rather than only in a comment:

```swift
@Test("Building returns an empty plan until catalog selection lands")
func buildIsEmptyForNow() {
    let plan = TemplatePlanBuilder.build(
        weekdays: [.monday, .wednesday], durationMinutes: 45,
        equipment: .fullGym, experience: .intermediate
    )
    #expect(plan.days.isEmpty)
}
```

- [ ] **Step 4: Verify the hardcoded names are gone**

```sh
grep -c "Barbell Bench Press\|Goblet Squat\|Pike Push-Up" LiftingPlan/Services/TemplatePlanBuilder.swift
```

Expected: `0`.

- [ ] **Step 5: Commit**

```sh
git add LiftingPlan/Services/TemplatePlanBuilder.swift LiftingPlanTests/TemplatePlanBuilderTests.swift
git commit -m "Delete the hardcoded exercise list from TemplatePlanBuilder"
```

---

### Task 7: Repair the views and surface save failures

The last task. Every view referencing the old models is updated, and all nine
`try? context.save()` call sites become real error handling.

**Files:**
- Modify: `LiftingPlan/LiftingPlanApp.swift`, `Views/RootView.swift`, `SetupView.swift`, `SettingsView.swift`, `PlanOverviewView.swift`, `SessionDetailView.swift`, `ActiveWorkoutView.swift`, `HistoryView.swift`, `Views/Components/SetRowView.swift`, `Services/PlanCoordinator.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–6.
- Produces: a compiling, running app on the new store.

- [ ] **Step 1: Point the app at the new container**

In `LiftingPlanApp.swift`, replace the existing model container with
`StoreContainer.cloudKit()`. A container failure is unrecoverable and must
surface — do not silence it with `try?`.

- [ ] **Step 2: Add the CloudKit entitlements**

The project needs the iCloud capability with CloudKit enabled, a container
identifier, and the remote-notification background mode. Without these,
`StoreContainer.cloudKit()` throws at launch.

If you cannot add entitlements from the command line, **stop and report** —
this is a step the human may need to do in Xcode's Signing & Capabilities
editor. Do not work around it by silently falling back to `inMemory()`; a
container that quietly stops persisting is exactly the class of silent failure
this plan exists to remove.

- [ ] **Step 3: Replace every `try? context.save()`**

All nine call sites. Each becomes a `do/catch` that surfaces the failure to the
user — the views already have somewhere to put an alert, or add one. A caught
error must reach the UI; logging alone reintroduces the original bug in a
quieter form.

Verify none remain:

```sh
grep -rn "try? context.save()\|try? modelContext.save()" --include="*.swift" LiftingPlan
```

Expected: no output.

- [ ] **Step 4: Update the views for the new model shapes**

`TrainingPreferences` becomes `UserProfile`, with training days and duration moving onto `TrainingPlan`;
`SetLog` becomes `LoggedSet` with `load: Mass?` instead of `weight: Double?`;
`PlannedExercise.name` becomes `displayName`; `WorkoutSession` becomes
`WorkoutDay` and now hangs off a `TrainingWeek` rather than directly off a plan. Weight entry and display go
through `profile.displayUnit`.

- [ ] **Step 5: Run the full suite**

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | grep -E "Test run with|✘|error:"
```

Expected: a clean build and every test passing. Report the count.

- [ ] **Step 6: Run the app on the simulator**

Launch it, complete setup, and confirm it reaches the main tabs without
crashing. **The tests passing does not prove the app runs** — a CloudKit
container misconfiguration fails at launch, not at test time.

```sh
xcrun simctl boot "iPhone 16" 2>/dev/null; \
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Then install and launch it, and report what you see. If it crashes at launch,
report the crash rather than disabling CloudKit.

- [ ] **Step 7: Commit**

```sh
git add -A LiftingPlan
git commit -m "Move the app onto the new store and surface save failures"
```

---

## What this plan does not cover

Deliberately deferred to the Services plan that follows:

- Rebuilding `TemplatePlanBuilder`'s selection against the 412-entry catalog.
- Routing `PlanGenerator` output through `ExerciseResolver`, so a generated
  name that does not resolve is never persisted.
- The programming rules from `2026-08-14-workout-programming-design.md`:
  pattern-based splits, push/pull balance, sticky exercise selection.
- The modern-minimal design system and the conversational onboarding, which
  remain sequenced after that.

After this plan the app runs on a store where weights carry units and exercises
carry stable identity — but plan generation returns empty, because the honest
seam is better than the old hardcoded list.
