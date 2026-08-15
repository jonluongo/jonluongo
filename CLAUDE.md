# LiftingPlan

iOS app that turns casual lifting into progressively harder training. SwiftUI,
SwiftData with CloudKit sync.

**The app makes no training decisions.** It is the blocks, the record, and the
interface: it owns the exercise catalog and the training log, answers questions
about them, displays plans, and logs sets. Claude — reached over MCP, built in a
later plan — makes every training decision: the split, the exercises, sets,
reps, rest, load, and what changes after an injury.

There is no plan generator in the app, and deliberately no fallback one. Until
Claude writes a plan, the app shows an empty state. If you find yourself adding
code that decides what someone should train, stop: that is the one thing this
app does not do.

The single thing the app insists on is data integrity — real `ExerciseID`s,
because history is keyed by exercise identity and a fabricated key fragments a
lift's history irreparably. That is not a decision, it is the difference
between a database and a pile of text.

## Build and test

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Device builds sign with `DEVELOPMENT_TEAM = GKMVG76BQR` and need
`-allowProvisioningUpdates`.

## Architecture

Four layers. **A layer may import only the layers above it.** This is the most
important rule in the project.

| Layer | Contents | May import |
|---|---|---|
| `Domain/` | Pure value types and logic. No persistence, no UI. | Foundation only |
| `Catalog/` | Bundled reference data — the exercise catalog and the assembly rules — plus lookup and resolution. | Domain |
| `Store/` | SwiftData models. User data only. | Domain |
| `Services/` | Queries over stored data, timing, and the one mapping into the store. | Domain, Catalog, Store |
| `Views/` | SwiftUI. | All of the above |

`Domain/` importing nothing but Foundation is what makes the interesting logic
testable without a database, simulator, or model. Do not erode it.

`Services/` answers questions and maps data. It does not conclude anything about
training. `PerformanceHistory` and `ExerciseTrend` report what happened;
`RestTimerModel` counts down what was prescribed; `PlanBlueprint` is the single
place a plan enters the store — and it records what it was handed, never
clamping, flooring, capping, or defaulting a prescribed value.

`PlanBlueprint` currently has no producer in the app. That is expected: it is
the seam where Claude's plans will arrive. Do not "fix" it by writing something
that generates plans.

`Catalog/` holds bundled reference data, never SwiftData: it ships with the
app, is never written at runtime, and every file in it carries a `version`.
Exercise identity is the MoveKit slug (see
`docs/reference/movekit-exercise-slugs.txt`), so purchased animations drop in
without a mapping layer.

`assembly-rules.json` also lives there, but **nothing in the app decodes it.**
It is reference material for Claude — sensible splits, typical rest by role —
not rules the app applies. It is data about training, not a decision the app
makes.

Design specs live in `docs/superpowers/specs/`. Read the foundation
architecture spec before changing the data model.

## Standards

These are binding. Code that violates them is not done.

**Errors are handled or propagated, never discarded.** No `try?` that drops an
error on the floor. A failed save must surface to the user — with CloudKit
sync, save conflicts are expected, not exceptional.

**No force unwrapping, force try, or force casting** outside tests. If a value
is guaranteed present, express that in the type.

**Data over code.** Facts about training — the catalog, reference splits, rep
and rest guidance — live in versioned JSON, not in `switch` statements. No
numeric literal expressing a training opinion appears anywhere in Swift,
including as a `static let` constant or a default on a stored property.

**Record what you are given.** A prescribed value is stored exactly as
prescribed. No clamping a set count, no capping rest, no substituting a default
rep range, no seeding a load from a rule. If a value is missing, either model
its absence honestly (optional, or a documented empty state) or refuse — never
invent one. A plan the user sees must be the plan that was prescribed.

**Extensible taxonomies, not closed enums.** Muscle groups, equipment,
movement patterns, and categories are raw-value-backed structs with static
constants. Unknown values from data must round-trip intact rather than crash or
be silently dropped.

**Protocol seams at boundaries.** Layers depend on protocols, not concrete
types, so implementations can be swapped and faked.

**Tests before implementation.** The pure layers carry real coverage. The
exercise resolver and unit conversion are the highest-value suites in the
project — they are the guard on data integrity.

**Every public type answers three questions** in its doc comment: what it does,
how it is used, what it depends on. If a type cannot be understood without
reading its internals, the boundary is wrong.

**Warnings are errors.** Swift 6 language mode, strict concurrency.

**Files stay focused.** A file growing past roughly 300 lines is a signal it is
doing too much.

## Verification

Never claim work is complete without running the command and reading the
output. State what was run and what it printed. If tests fail, say so.

**Reading test output correctly.** Every test here uses Swift Testing, not
XCTest, so `xcodebuild test` prints a legacy line that looks alarming and means
nothing:

```
Test Suite 'All tests' passed. Executed 0 tests, with 0 failures
```

That is the XCTest reporter counting zero XCTest cases. It is expected. The
line that actually proves tests ran is:

```
✔ Test run with 23 tests in 4 suites passed after 0.018 seconds.
```

`** TEST SUCCEEDED **` alone does not prove anything ran — it prints even when
nothing executes. Always confirm the test count:

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 \
  | grep -E "Test run with|✘|error:"
```
