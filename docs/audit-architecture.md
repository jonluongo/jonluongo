# LiftingPlan Architecture Audit

Date: 2026-08-14
Scope: `LiftingPlan/` (40 source files) and `LiftingPlanTests/` (15 suites, 114 tests), against the layering and standards in `CLAUDE.md`. No code was changed.

---

## 1. Layer integrity

**The mechanical import rule holds with no violations.** Every file in `Domain/` imports only `Foundation`. `Catalog/` imports only `Foundation` and references Domain types. `Store/` imports `Foundation`/`SwiftData` and references Domain types. `Services/` stays within Domain/Catalog/Store. `Views/` is the only place `SwiftUI` appears. No file imports "sideways" or "up" the stack.

Conceptual leakage found beyond the import graph:

- **Important** — `LiftingPlan/Domain/TrainingEnums.swift:53` and `:71`. `Equipment.promptDescription` and `ExperienceLevel.promptDescription` are English sentences written specifically to be interpolated into an LLM prompt (`"an adjustable set of dumbbells and a bench"`, `"1–3 years of consistent training"`). They are consumed only by `PlanGenerator.prompt(...)` (`LiftingPlan/Services/PlanGenerator.swift:165-166`). This is a Service-layer formatting concern living on a Domain type. `Domain/` is supposed to be "pure value types and logic" — a value type that knows how to phrase itself for an AI prompt is presentation/service logic wearing a Domain costume. It doesn't break the import rule (Services is allowed to depend on Domain), but the dependency direction of *concern* is backwards: Domain now has a member that only makes sense because of how one specific Service formats one specific prompt. Moving `promptDescription`-equivalent text into `PlanGenerator` (e.g. a private `[Equipment: String]` / `[ExperienceLevel: String]` map, or a small protocol Services defines and Domain doesn't need to know about) would restore the boundary.

- **Minor** — `LiftingPlan/Views/HistoryView.swift:145-196`. `ExerciseTrend` and `TrendPoint`, plus `ExerciseTrend.build(from:)`, are non-UI value types and non-trivial domain logic (best-set selection, per-exercise grouping across the plan hierarchy, "isImproving" comparison) that live in a View file and import `SwiftUI`/`Charts` transitively through the file even though the types themselves don't need UI at all. This is the same shape of computation `Services/PerformanceHistory.swift` already does (see §2) — it is Service-layer work stranded in Views. Not a hard import violation (Views may depend on everything), but it inverts the intended shape: Views should consume Services, not reimplement them.

No Domain type reaches into Store internals, no Service mutates SwiftData models it doesn't own, and no persistence type (`@Model`) leaks into Domain. The `Store/` layer's convention of a private `xRaw: String` backing store plus a computed Domain-typed accessor (`UserProfile.swift:20-21`, `55-68`; `WorkoutDay.swift:33-36`; `TrainingPlan.swift:49-52`) is applied consistently everywhere it's needed — this is the strongest part of the codebase.

---

## 2. Coupling and cohesion

- **Important — duplicated business logic, not just duplicated code.** `Services/PerformanceHistory.swift:66-70` (`allExercises(in:)`) and `Views/HistoryView.swift:162-167` (`ExerciseTrend.build(from:)`) both independently walk `plans.flatMap(\.orderedWeeks).flatMap(\.orderedDays).flatMap(\.orderedExercises).filter { !$0.completedWorkingSets.isEmpty }`. Same traversal, same filter, written twice, in two different layers, with no shared helper. If the plan hierarchy ever grows a new level (the specs already discuss multi-week blocks), both call sites have to be found and updated in lockstep, and only one of them is unit-tested (see §5).

- **Important — the same helper function copy-pasted verbatim across layers-within-Views.** `formatRest(_:)` is defined identically in `Views/ActiveWorkoutView.swift:250-257` and `Views/Components/ExerciseLogSection.swift:104-111`. Same body, same rounding rules, two private copies. Likewise the `restOptions = [30, 45, 60, 75, 90, 120, 150, 180]` array is a literal duplicated in both files (`ActiveWorkoutView.swift:20`, `ExerciseLogSection.swift:20`).

- **Important — the same error-handling boilerplate repeated five times.** The pattern
  ```swift
  private var errorAlertBinding: Binding<Bool> {
      Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }
  ...
  errorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
  ```
  appears with only the stored-property name changed in `RootView.swift`, `PlanOverviewView.swift`, `ActiveWorkoutView.swift`, `SetupView.swift`, and `SettingsView.swift`. This is exactly the kind of repetition a `View` extension (`func errorAlert(_ message: Binding<String?>) -> some View`) or an `Error` extension (`var userFacingDescription: String`) exists to remove. None of these five files are wrong individually; together they are one un-DRY'd concept with five owners, so a future change to how save errors are surfaced (e.g. adding a retry button) means five edits, and it is easy to update four and miss one.

- **Minor — no god object.** No single type accumulates outsized responsibility. `PlanGenerator` (254 lines) is the closest thing to a "does a lot" type — it owns availability tracking, prompt construction, the guided-generation schema, and fallback selection — but each concern is a distinct, separately-testable static/private method, and the file stays under the project's own 300-line signal threshold. `ActiveWorkoutView` (297 lines) is right at that threshold; it is legible today because seeding, saving, and toolbar chrome are cleanly sectioned with `// MARK:`, but it has no headroom left before it should be split (e.g. extracting the seeding logic into a small service, mirroring what `ExerciseLogSection` already did for the per-row UI).

- **Minor — brittle-by-shape types are the deliberately-thin ones, which is correct.** `PlannedExercise`, `TrainingPlan`, etc. would be painful to change because many things depend on their exact shape, but that shape is intentional (CloudKit's every-property-must-default rule), documented, and covered by `StoreModelTests.cloudKitCompatible()` and `LifterDataTests.cloudKitCompatible()`. This is appropriate coupling to an external constraint, not accidental coupling to a design choice — no finding here.

---

## 3. Dead, vestigial, or half-finished code

Two stubs are known-and-documented per the task brief and are **not** counted as defects: `TemplatePlanBuilder.build` (`Services/TemplatePlanBuilder.swift:17-24`) returns an empty plan, and `PlanGenerator.blueprint(from:...)` (`Services/PlanGenerator.swift:194-216`) discards the model's exercises and returns day skeletons only. Both carry clear "why" comments pointing at the design spec.

Beyond those two, genuinely dead or vestigial items found:

1. **Important** — `LiftingPlan/Services/PlanBlueprint.swift:34`. `ExerciseBlueprint.muscleGroup: String` is written by every call site that constructs an `ExerciseBlueprint` (all of them currently in tests only — see #2) but is never read anywhere, including inside `PlanBlueprint.makeWorkoutPlan(...)` itself (`PlanBlueprint.swift:53-84`), which maps `exerciseID`, `displayName`, `sets`, `repRange`, `suggestedLoad`, `restSeconds`, `tempo`, and `notes` onto `PlannedExercise` but never touches `.muscleGroup`. It is a field that exists, is populated, and goes nowhere.

2. **Important** — `LiftingPlan/Services/PlanBlueprint.swift:31-41`. `ExerciseBlueprint` itself has zero production call sites. `grep -rn "ExerciseBlueprint("` across `LiftingPlan/` matches nothing; it only appears in `LiftingPlanTests/PlanMappingTests.swift`. This is a direct consequence of the two documented stubs (nothing currently produces a populated `exercises: [ExerciseBlueprint]`), so it's expected to stay this way until that work lands — but as it stands today it is a fully-specified type, hand-tested, that no runtime path constructs.

3. **Important** — `LiftingPlan/Services/PlanGenerator.swift:238-253`. `GeneratedExercise` (and the `exercises: [GeneratedExercise]` field on `GeneratedDay`) is a complete `@Generable` schema with five `@Guide`-annotated fields (name, muscleGroup, sets, repRange, restSeconds, tempo, notes). The on-device model is actively asked to produce this data on every generation call — burning inference budget and prompt/response tokens — and then `Self.blueprint(from:...)` (`PlanGenerator.swift:194-216`) reads only `g.focus` from each generated day and drops `g.exercises` on the floor entirely. This is a step beyond the documented stub: it's not just "the wiring isn't in place," it's "the model is asked to do the work and the answer is thrown away every single time." Worth a comment noting this is a known cost of the current milestone, at minimum — a reader who hasn't traced `blueprint(from:...)` line by line would reasonably assume `exercises` gets used.

4. **Important** — `LiftingPlan/Services/TemplatePlanBuilder.swift:27-36`. `splitTemplate(forDayCount:)` is never called by `build(...)` (which ignores it and returns `PlanBlueprint(days: [])` unconditionally) or by any other production code — `grep -rn "splitTemplate"` outside tests returns nothing. It is exercised only by `TemplatePlanBuilderTests.splitByDayCount()`. Unlike `ExerciseBlueprint`, this isn't obviously part of the documented seam (the doc comment on `build` doesn't mention it); it reads like a leftover fragment from a previous implementation of `build` that hasn't been deleted or reconnected.

5. **Minor** — `LiftingPlan/Services/PlanGenerator.swift:44-72`, `refreshAvailability()` is `public`-visible (internal) API called both from `init()` and from `generatePlan(...)`, but is also directly callable by Views — no View currently calls it (checked `Views/*.swift`), so it is only reachable through the two internal call sites today. Not dead, just wider surface than used; low priority.

No unreferenced Store models, no orphaned Catalog code, and no `try?`-discarded errors were found anywhere in `LiftingPlan/` — the only occurrence of the string `try?` in the whole source tree is inside a doc comment explaining why *not* to use it (`Store/PersistenceError.swift:32`). No force-unwrap (`!`), `as!`, or `try!` was found outside of expected patterns.

---

## 4. Naming and consistency

- **Consistent and clean naming pattern across layers.** Domain taxonomies (`MuscleGroup`, `EquipmentType`, `MovementPattern`, `ForceType`, `Mechanic`, `Difficulty`, `ExerciseCategory`) all follow the identical `ExtensibleTaxonomy` shape and naming convention (`Taxonomies.swift`). Store models consistently pair a private `xRaw` storage property with a public computed `x` accessor of the Domain type. `orderedX` is used consistently for every SwiftData-unordered-relationship accessor (`orderedWeeks`, `orderedDays`, `orderedExercises`, `orderedMessages`, `orderedWeekdays`) — a reader who learns the convention once can predict it everywhere.

- **Minor — two names for adjacent but different concepts that are easy to conflate.** `Equipment` (Domain, `TrainingEnums.swift:45` — the lifter's *access tier*, e.g. `.fullGym`) and `EquipmentType` (Domain, `Taxonomies.swift:39` — a *specific catalog requirement*, e.g. `.barbell`) are distinct on purpose and `EquipmentAccess.swift`'s doc comment explains the relationship well. But the names alone (`Equipment` vs. `EquipmentType`) don't signal that distinction — a newcomer skimming autocomplete would have no way to guess which one is the coarse tier and which is the precise requirement without opening the file. A more self-explanatory pair (e.g. `EquipmentAccessTier` / `EquipmentType`, or `EquipmentAccess` / `EquipmentRequirement`) would remove the need to hold the distinction in your head.

- **Minor — `Weekday` vs. weekday-as-Int rawValue duplicated across three Store models.** `TrainingPlan.weekdayRawValues: [Int]`, `WorkoutDay.weekdayRawValue: Int` each independently reimplement the "store as raw Int, expose as `Weekday`/`Set<Weekday>`" pattern (correctly and consistently, per §4's first bullet) but with three near-identical getter/setter pairs that could be one small shared helper (e.g. a `RawRepresentableCollection` property wrapper or a static mapping function on `Weekday`). Not a bug, just three copies of the same small idiom.

- No instance of one concept having two different names, and no misleading names, were found.

---

## 5. Testability and test quality

The 114 tests sampled (all 15 suites read in full or in large part) are **behavior tests, not shape tests** — they assert on outcomes tied to real bugs and real invariants (e.g. `CatalogIntegrityTests.slugMuscleAgreement()` encodes a specific past data-quality regression; `ExerciseResolverTests` and `ProgressionEngineTests` assert on the actual numbers the algorithms should produce, not just that they return "something"). This is a genuine strength — the guard-rail tests CLAUDE.md calls out as highest-value (resolver, unit conversion) are in fact the most thorough suites in the repo.

Two testability gaps found:

- **Important — the HistoryView trend logic (§2, §3) has no test coverage at all.** `grep -rln "ExerciseTrend\|TrendPoint" LiftingPlanTests/` returns nothing. `ExerciseTrend.build(from:)` does real work — grouping, "top set" selection with a tie-break rule, `isImproving` comparison — comparable in complexity to `PerformanceHistory.histories(from:)`, which *is* thoroughly tested. Because the type lives in a View file, it fell outside the "pure layers carry real coverage" discipline the rest of the project follows. This is both a testability finding and evidence for consolidating it into `Services/` (§1, §2): moving it there would put it back under the same test discipline as its sibling.

- **Minor, expected** — `TemplatePlanBuilderTests.buildIsEmptyForNow()` and `.emptyWeekdays()` (`LiftingPlanTests/TemplatePlanBuilderTests.swift:15-28`) pass for any implementation that returns an empty plan, including a completely broken one — they assert the documented stub behavior, nothing more. This is expected and appropriate given `build`'s current state (§3); flagging only so it's not mistaken for coverage of exercise-selection logic once that logic is implemented — the test will need to be replaced, not extended, at that point.

Test structure mirrors source structure sensibly: `CatalogIntegrityTests`, `ExerciseCatalogTests`, `ExerciseResolverTests`, `ExerciseDecodingTests` line up with `Catalog/`; `StoreModelTests`, `LifterDataTests`, `PersistenceErrorTests` line up with `Store/`; `ProgressionEngineTests`, `RestTimerTests`, `TemplatePlanBuilderTests`, `PlanMappingTests` line up with `Services/`; `MassTests`, `RepRangeTests`, `TaxonomyTests`, `EquipmentAccessTests` line up with `Domain/`. There is no `Views/` test coverage at all (no snapshot/UI tests), which is a reasonable and common choice for a SwiftUI app, but it is the reason the `HistoryView` gap above went unnoticed — nothing outside `Views/` exercises that code, and nothing inside `Views/` is tested.

---

## 6. Doc comment compliance

**Domain, Catalog, Store, and Services follow the what/how/depends-on standard rigorously and it has not degraded.** Every sampled type in these four layers (`ExerciseID`, `Exercise`, `ExtensibleTaxonomy`, all six taxonomy structs, `Mass`, `RepRange`, `EquipmentAccess`, `ExerciseCatalog`, `ExerciseResolver`, `ResolvedExercise`, every `Store/` `@Model`, `PlanBlueprint`/`DayBlueprint`/`ExerciseBlueprint`, `PerformanceHistory`, `ExerciseHistory`, `ProgressionEngine`, `RestTimerModel`, `TemplatePlanBuilder`) closes with an explicit "Depends on: ..." sentence and states both what the type is for and how/where it's meant to be used (often citing the specific caller by name, e.g. "Used by `PerformanceHistory` to seed a set's rep count..."). This is unusually well maintained for a codebase this size and is the standout positive finding of the audit.

- **Minor — the standard visibly drops off inside `Views/`.** Doc comments there are almost universally a single descriptive sentence with no "how it's used" and no "depends on" (e.g. `TimerRing`: "A circular countdown ring for the rest timer, with the time in the center." — `Views/Components/TimerRing.swift:3`; `WeekdayChips`: "A row of tappable day chips for choosing which days to train." — `Views/Components/WeekdayChips.swift:3`). For most of these that's a reasonable relaxation — a `View` struct's dependencies are its stored properties, visible one line below — but it means the standard as written ("every public type") is being applied selectively by layer rather than uniformly, and the two non-UI types that got stranded in Views (`ExerciseTrend`, `TrendPoint` — §1, §5) inherited that laxer treatment even though they're exactly the kind of type the standard exists for: `TrendPoint`'s doc is one line ("One session's top-set result for an exercise.") with no depends-on, despite carrying a non-obvious invariant (`estimatedOneRepMaxKilograms` is deliberately kept in kilograms rather than display units — that rationale is documented on the property itself, one line down, just not surfaced in the type's own doc).
- No instance of a doc comment merely restating the type name was found — even the terse `Views/` comments say something real about the type's purpose.

---

## Summary

| Area | Verdict |
|---|---|
| Layer integrity (imports) | Holds with zero violations |
| Layer integrity (concepts) | One real leak (`promptDescription` on Domain enums) |
| Coupling/cohesion | No god object; several small un-DRY'd duplications, one duplicated business-logic path |
| Dead/vestigial code | 4 items beyond the 2 documented stubs (`ExerciseBlueprint`/`muscleGroup` unused, `GeneratedExercise` discarded, `splitTemplate` orphaned) |
| Naming | Consistent; one ambiguous pair (`Equipment`/`EquipmentType`) |
| Testability | Strong in tested layers; one real gap (`HistoryView`'s trend logic, untested) |
| Doc comments | Rigorous in Domain/Catalog/Store/Services; relaxed (not degraded-from-restating-the-name, just thinner) in Views |
