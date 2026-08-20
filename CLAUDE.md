# LiftingPlan

iOS app that turns casual lifting into progressively harder training. SwiftUI,
SwiftData with CloudKit sync.

**The app makes no training decisions.** It is the blocks, the record, and the
interface: it owns the exercise catalog and the training log, answers questions
about them, displays plans, and logs sets. Claude — reached over MCP, which is
built and running — makes every training decision: the split, the exercises,
sets, reps, rest, load, intensity, how a block progresses week to week, and what
changes after an injury.

There is no plan generator in the app, and deliberately no fallback one. Until
Claude writes a plan, the app shows an empty state. If you find yourself adding
code that decides what someone should train, stop: that is the one thing this
app does not do.

**The app also asks the lifter nothing.** There is no onboarding, no setup
screen, and no settings form for a training question — days, session length,
goal, equipment, experience and injuries are all things Claude asks better in
conversation, and he records them with the `update_profile` tool. The one
preference left is whether the rest clock runs at all, which is about this phone
rather than about the lifter. Even lb/kg is Claude's: pounds or kilos is a fact
about how the lifter thinks, he says it in conversation like anything else, and
`ProfileUpdate.displayUnit` carries it. A toggle for it was the app asking a
question. A profile that has been told nothing must read as
*not known*, never as a plausible default: `experience` is optional for exactly
that reason, and `availableEquipment` is absent rather than empty when nobody
has said — `nil` is "nobody asked", `[]` is "owns nothing", and the two must
never collapse. Do not add a form, and do not add a default that asserts
something about a lifter nobody ever asked.

Equipment is **an open set of what he owns**, not a tier. The four `Equipment`
tiers survive only as input shorthand that expands at the boundary; nothing
stores one, and nothing may reintroduce one as the vocabulary.

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

The tests live in three places. **All three must be run** — the app suite alone
covers neither the catalog, the taxonomies, `Mass` and `RepRange`, nor the
document formats and the MCP tools:

```sh
swift test --package-path LiftingKit
swift test --package-path LiftingMCP
```

Xcode compiles a package dependency with `-suppress-warnings`, so the package
cannot declare warnings-as-errors in its manifest without breaking the app
build. Enforce the standard on the package explicitly:

```sh
swift build --package-path LiftingKit -Xswiftc -warnings-as-errors
swift build --package-path LiftingMCP -Xswiftc -warnings-as-errors
```

Device builds sign with `DEVELOPMENT_TEAM = GKMVG76BQR` and need
`-allowProvisioningUpdates`.

## Architecture

Four layers. **A layer may import only the layers above it.** This is the most
important rule in the project.

| Layer | Where it lives | Contents | May import |
|---|---|---|---|
| `Domain/` | `LiftingKit` package | Pure value types and logic. No persistence, no UI. | Foundation only |
| `Catalog/` | `LiftingKit` package | Bundled reference data — the exercise catalog and the assembly rules — plus lookup and resolution. | Domain |
| `Store/` | app target | SwiftData models. User data only. | LiftingKit |
| `Services/` | app target | Queries over stored data, timing, and the one mapping into the store. | LiftingKit, Store |
| `Presentation/` | app target | Pure logic turning models into what a screen states — phrasing, prescriptions, row readings, formatting. No SwiftUI. | LiftingKit, Store |
| `Views/` | app target | SwiftUI, and nothing else. | All of the above |

`Domain/` importing nothing but Foundation is what makes the interesting logic
testable without a database, simulator, or model. Do not erode it.

The first two layers are a local Swift package, `LiftingKit/`, which the app
consumes. It is the shared *vocabulary*: what an exercise is, what a weight is,
what the catalog contains. A macOS MCP server links the same package, so the two
clients cannot disagree about any of it.

**`Store/` deliberately stays in the app.** The server reads a snapshot file and
must never link SwiftData; moving the models into the package would drag
SwiftData into a command-line tool for nothing.

The package's public surface is kept small on purpose. Something used only by
tests stays internal — the suites use `@testable import LiftingKit` rather than
widening the API.

`Presentation/` is where the app's most testable code lives, and it was scattered
through `Views/` because that is where each piece was first needed. A type that
turns a `PlannedExercise` into `"3 × 6-8 · 80% effort"` is not a view — it holds
no state, draws nothing, imports no SwiftUI, and is worth testing against
strings. The test for the folder is mechanical: **if it does not import SwiftUI,
it does not live in `Views/`.**

`Services/` answers questions and maps data. It does not conclude anything about
training. `PerformanceHistory` and `ExerciseTrend` report what happened;
`RestTimerModel` counts down what was prescribed; `RoutineBlueprint` is the
single place a plan enters the store — and it records what it was handed, never
clamping, flooring, capping, or defaulting a prescribed value.

`RoutineBlueprint` is the seam where Claude's plans arrive, and it has exactly
one producer: `PlanImporter`, building it from a decoded `PlanDocument`. That is
the only producer it may ever have. Do not add one that generates plans.

**A plan document already in the store is merged, not ignored.** That is what
lets the coach write a week at a time: he sends the routine's `id` with one more
block on it, and `PlanImporter.merge` appends it. He may rewrite any block
nothing has been logged against and may not touch one that has — a set the
lifter ticked is the record of what happened, and a plan that rewrites it is
refused by ordinal with nothing taken in. See *The loop* in `docs/decided.md`.

**The way back out is the document itself.** `PlanDocument(reconstructing:)`
reads a stored block into the document it was imported as, and
`SnapshotExporter` sends that rather than a second description of it. A
prescription used to exist in three vocabularies — the document, the `@Model`s,
and a tree of snapshot types — and the first and third disagreed about how a
superset is written. There are two now, and the round-trip suite is what says
the store holds everything the document stated. Do not add a third: a type that
restates a prescription for a reader is the shape this cost a rewrite to
remove.

`Catalog/` holds bundled reference data, never SwiftData: it ships inside the
package, is never written at runtime, and every file in it carries a `version`.
The files resolve through `Bundle.module`, not the app bundle. A resource that
fails to resolve does not look like an error — it looks like an empty catalog —
so `CatalogIntegrityTests` asserts both files load rather than trusting the
build to have copied them.
Exercise identity is the MoveKit slug (see
`docs/reference/movekit-exercise-slugs.txt`), so purchased animations drop in
without a mapping layer.

`assembly-rules.json` also lives there, but **nothing in the app decodes it.**
It is reference material for Claude — sensible splits, typical rest by role —
not rules the app applies. It is data about training, not a decision the app
makes.

**One rename is held open, and `docs/decided.md` opens with it.** The store's
`@Model` names — `TrainingPlan`, `TrainingWeek` — still use the old vocabulary,
because SwiftData derives the CloudKit record type from the entity name and a
rename without a tested migration opens the store empty with the data still in
the container. It is held, not forgotten, and the work it needs is written down.
The wire is done: `plan.json` states `blocks` from version 5 and the snapshot
`blockOrdinal` from version 4, both reading the older spelling.

`docs/decided.md` records what is settled and what was tried and killed, with the
reason for each. **Read it before proposing anything on it.** A long session gets
compacted and the reasoning goes first, so the predictable failure is not
forgetting but confidently re-proposing a rejected idea. That file is the guard.

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

**A set is counted, held, or carried, and no two of them are the same number.**
A rep target is read by `RepRange`, a hold by `WorkDuration` and a carry by
`WorkDistance`; they share one vocabulary and one scan in `TargetUnits`, and
they claim a target in a fixed order so two of them never claim the same one.
`WorkMeasure` gives the single answer everything downstream binds to — one value
with three cases, never a set of booleans that could say two things at once. A
logged set carries `reps`, `durationSeconds` and `distance` as separate fields,
and which one a row writes is decided by what was prescribed for it, never by
what was typed. Nothing may add seconds or metres into a rep total — that is a
number nobody performed, and it propagates into every report that follows. A
distance keeps the unit it was prescribed in and is never converted, exactly as
`Mass` keeps its own; two units are reported side by side rather than summed. A
hold that was not timed and a carry that did not happen are `nil`, never zero.

Adding a fourth measure means adding a case to `WorkMeasure`, which will not
compile until every place that logs one has been told what to do with it. That
is deliberate — it is what stops the next measure from landing in the rep column
the way a hold once did.

**Data earns its place or it goes.** A stored field, a document key, a
catalog column exists because something reads it and someone is better off for
that. When nothing does, it is removed — the property, its migration, its
tests, its mention in every doc comment — rather than left in place because it
is cheap. Cheap is the argument that fills a schema with columns nobody can
explain, and a field nobody can explain is a field nobody dares delete.

The test is utility, not age. Some data looks dead and is not: the retired
`equipmentAccessRaw` and `hasCompletedSetup` on `UserProfile` are read by
exactly one thing — the migration that tells equipment the lifter *stated* from
the `fullGym` a deleted setup form filled in for him. They stop earning their
place the day every install has opened a build that migrates, and that is when
they go. Ask what reads it and who is worse off without it; if the answer is
nothing and nobody, remove it completely.

**Refuse rather than discard.** An inbound document stating a key this format
does not have is refused with the key named and nothing taken in — never read
around. A silently dropped key tells the writer his prescription landed when
none of it did, which is the only failure here that reports success. The rule
lives in `DocumentRefusal` in LiftingKit so the phone and the macOS server
cannot answer it differently.

**Every inbound format is versioned, and skew is refused, not guessed.** Both
documents carry a `version`; a reader handles an older one and refuses a newer
one *whole*, naming both versions, before holding any key against it — an
unknown key is exactly what a later format is made of. Bump the version when a
reader would have to behave differently, never for an additive field.

**An icon does one of three jobs, or it does not exist.** Either it *names an
action* where a word will not fit — a toolbar control, a menu item —
or it *marks a state that varies* within a list, where the variation is the
information: a logged day beside an unlogged one, a superset beside a plain
exercise — or it is *a mark Claude chose*, from a closed set the app publishes
and refuses anything outside. Anything else is decoration.

The third case is what a session's mark is. The app must never pick one: a
glyph inferred from `Push` or `Upper A` is the app deciding what a session
trains from words it does not control, and one deriving it from the exercises
is the app deciding what they add up to. `SessionIcon.all` is the vocabulary,
`write_plan` offers it, `PlanImporter` refuses a name this build cannot draw,
and a day he marked nothing carries nothing. Which system symbol a name is
drawn as lives in `SessionIconView` and nowhere else — that is the app's
business, and changing it must not be a change to the format he writes.

The test is the one the owner set: **an icon identical everywhere it appears
distinguishes nothing** — and its pair, **an icon that varies must vary along
one axis.** A dumbbell for the block being trained against a calendar for one
behind him was two different subjects in one slot, so the change from one to the
other read as noise; both went, and the rows say it in words instead. That is why every exercise header lost its dumbbell and
every group its rotate arrows, and why a day row has none — the day's name is
whatever Claude called it, so a glyph per session would mean the app deciding
what a session trains from words it does not control.

**SF Symbols only, and no third-party set.** They already match the system's
optical weight, scale with Dynamic Type, and follow the appearance. A bundled
pack costs assets, a licence and hand-matched weights, and buys no information —
and there is no icon set that meaningfully covers 412 movements, so per-exercise
glyphs would be guesswork about what a lift *is*. One symbol per job, drawn from
the system.

**Extensible taxonomies, not closed enums.** Muscle groups, equipment,
movement patterns, and categories are raw-value-backed structs with static
constants. Unknown values from data must round-trip intact rather than crash or
be silently dropped.

**Protocol seams at boundaries.** Layers depend on protocols, not concrete
types, so implementations can be swapped and faked.

**Tests before implementation.** The pure layers carry real coverage. Unit
conversion and the two refusals — an `ExerciseID` the catalog lacks, a document
key this format does not have — are the highest-value suites in the project,
because they are the guard on data integrity. (`ExerciseResolver` has a suite of
its own and no callers: plans arrive as catalog IDs and unknown ones are
refused, so nothing resolves free text. Its doc comment says so.)

**Every public type answers three questions** in its doc comment: what it does,
how it is used, what it depends on. If a type cannot be understood without
reading its internals, the boundary is wrong.

**Warnings are errors.** Swift 6 language mode, strict concurrency.

**Files stay focused.** A file growing past roughly 300 lines is a signal it is
doing too much.

## Verification

**Render everything a change touches.** A screenshot of the screen being worked
on is not verification — it is verification of that screen. Four defects in one
sprint were siblings of a screen that had been rendered: panel insets applied to
two callers of five, a completed-row background left on the group table after it
was deleted from the exercise table, a Done button left on one sheet of three.
When a shared modifier, token or shape changes, list its callers and look at each
one. A component with two callers has two screenshots owing.

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
