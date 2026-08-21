# LiftingPlan

iOS app that turns casual lifting into progressively harder training. SwiftUI,
SwiftData with CloudKit sync.

> **A rebuild is in progress on `claude/backend-rebuild`.** This file describes
> the architecture being built. `docs/rebuild-spec.md` holds the formats and the
> phase order, `docs/rebuild-inventory.md` the verdict on every file, and
> `docs/decided.md` the reasoning behind all of it. Read `decided.md` before
> proposing anything: it records what was tried and killed, and confidently
> re-proposing a rejected idea is the predictable failure of a long session.

**The app is two things: a datastore, and the interface an AI trainer works
through.** Anything that is neither is bloat. That is the filter for every
proposal.

**The app makes no training decisions.** It owns the exercise catalog and the
training log, answers questions about them, displays plans, and logs sets.
Claude — reached over MCP — decides the split, the exercises, sets, reps, rest,
load, intensity, how a block progresses, and what changes after an injury.

There is no plan generator and deliberately no fallback one. Until Claude writes
a plan, the app shows an empty state. If you find yourself adding code that
decides what someone should train, stop: that is the one thing this app does not
do.

**The app also asks the user nothing.** No onboarding, no setup screen, no
settings form for a training question. Days, session length, goal, equipment,
experience and injuries are things Claude asks better in conversation, and he
writes them into `ACCOUNT.md`. The one preference the app owns is whether the rest
clock runs at all — that is about this phone, not about the user, so it lives
in `UserDefaults` and never syncs.

**The single thing the app insists on is data integrity — real `ExerciseID`s.**
History is keyed by exercise identity, and a fabricated key fragments a lift's
history irreparably. That is not a decision, it is the difference between a
database and a pile of text.

## The loop

> The coach reads `ACCOUNT.md`, `PROGRAM.md` and the performed tables, and writes
> prescriptions. The app draws them and logs against them.

| File | Written by | Read by |
|---|---|---|
| `snapshot.json` | phone | server |
| `plan.json` | server | phone |
| `plans/<id>.json` | phone, on import | the archive — every plan taken in |
| `ACCOUNT.md`, `PROGRAM.md` | server | phone, **rendered, never parsed** |
| `notes/<file>.<timestamp>.md` | server, before each edit | the versions |

**The phone is the only writer of the record**, so a reliable export is always
current. It exports on Finish, debounced after any logged set, and on
backgrounding under a background-task assertion — not, as it once did, only
while being suspended with seconds to resolve an iCloud container.

**Markdown is rendered and never parsed.** Nothing is read *out* of prose. The
moment a number must come out of a file, that number belongs in a table.
Writes to it are anchored edits — `{file, old_text, new_text}`, refused whole if
the anchor is missing or ambiguous — because prose has no other refusal
machinery. A prior copy is kept before every edit, and dated facts append.

## Build and test

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**All three suites must be run.** The app suite covers neither the catalog, the
taxonomies, `Mass` and `Target`, nor the document formats and the MCP tools:

```sh
swift test --package-path LiftingKit
swift test --package-path LiftingMCP
```

Xcode compiles a package dependency with `-suppress-warnings`, so the standard
is enforced on the packages explicitly:

```sh
swift build --package-path LiftingKit -Xswiftc -warnings-as-errors
swift build --package-path LiftingMCP -Xswiftc -warnings-as-errors
```

Device builds sign with `DEVELOPMENT_TEAM = GKMVG76BQR` and need
`-allowProvisioningUpdates`.

**iCloud delivery cannot be judged at the moment of a write.** For the first
seconds a new file reads *not uploaded, not uploading, error present* — which is
what iCloud looks like before it picks the file up, not a refusal. Anything that
asks then and reports the answer will tell the user his setup is broken while it
works. Ask about a file iCloud has had time to decide on, or report only what is
knowable immediately: whether the folder is a ubiquity container at all.

**A quiet error list is not a green build.** `xcodebuild` fails fast: it stops
after a batch of files, so grepping its output for errors reports only what it
reached. Twice in one session a phase was declared finished on that signal while
files it owned had never been compiled at all — they named types that no longer
existed and nothing had looked. **The only completion signal is
`** BUILD SUCCEEDED **`**, and for the packages, `Build complete!` plus a test
count. When checking whether a layer is done, grep the sources for the names of
what was deleted; the compiler will not volunteer a file it never opened.

**A stale dependent looks exactly like data corruption.** Adding a stored
property to a `public struct` in LiftingKit changes its layout, and a dependent
package whose objects were not rebuilt reads strings at the wrong offset — `"8"`
decoding as `"\0"`, length intact. When a package suite fails with values that
look *mangled* rather than *wrong*, delete its `.build` directory before
debugging it.

## Architecture

Four layers. **A layer may import only the layers above it.** This is the most
important rule in the project.

| Layer | Where it lives | Contents | May import |
|---|---|---|---|
| `Domain/` | `LiftingKit` | Pure value types and logic. No persistence, no UI. | Foundation only |
| `Catalog/` | `LiftingKit` | Bundled reference data and lookup. | Domain |
| `Documents/` | `LiftingKit` | The wire formats and their refusals. | Domain, Catalog |
| `Store/` | app target | SwiftData models. User data only. | LiftingKit |
| `Services/` | app target | Queries over stored data, timing, and the one mapping into the store. | LiftingKit, Store |
| `Presentation/` | app target | Pure logic turning models into what a screen states. No SwiftUI. | LiftingKit, Store |
| `Views/` | app target | SwiftUI, and nothing else. | All of the above |

`Domain/` importing nothing but Foundation is what makes the interesting logic
testable without a database, simulator, or model. Do not erode it.

**`Store/` deliberately stays in the app.** The server reads a snapshot file and
must never link SwiftData; moving the models into the package would drag
SwiftData into a command-line tool for nothing.

The package's public surface is kept small on purpose. Something used only by
tests stays internal — the suites use `@testable import LiftingKit` rather than
widening the API.

**If it does not import SwiftUI, it does not live in `Views/`.** A type that
turns a prescription into `"3 × 6-8 · 80% effort"` holds no state, draws
nothing, and is worth testing against strings.

### The store — five tables

```
Session
  PlannedExercise   →   PerformedExercise
    PlannedSet      →     PerformedSet
```

**Intent and event never share a table.** That one rule produces the rest.

- **`Session`** — one workout the coach prescribed. `blockOrdinal`, `ordinal`,
  `focus`, `icon`, `finishedAt`, `generatedAt`, `catalogVersion`,
  `sourceDocumentID`. It has no date: *when* he trained is a fact about the
  record.
- **`PlannedExercise`** → Session — `exerciseID`, `order`, `restSeconds`,
  `coachNote`, `groupOrdinal`.
- **`PlannedSet`** → PlannedExercise — `setIndex`, `isWarmup`, `load`,
  `intensity`, `target`.
- **`PerformedExercise`** → Session, → PlannedExercise *(nullable)* —
  `exerciseID`, `occurredAt`, `userNote`, `source` (logged | stated).
- **`PerformedSet`** → PerformedExercise, → PlannedSet *(nullable)* —
  `setIndex`, `isWarmup`, `load`, `reps`, `durationSeconds`, `distance`,
  `completedAt`.

**Blocks are ordinals and have no names.** What makes block 3 an accumulation
block is a line in `PROGRAM.md`. Blocks run continuously and never restart.

**Every prescribed set is a row.** A ramp, a drop set and three identical sets
are one shape. There are no exercise-level defaults for a set to override — that
reconciliation was where a prescription could quietly become something the coach
did not write.

**A performed row exists only if it happened.** No seeding, so no `isCompleted`:
the row's existence is the fact.

**Both nullable links are meaningful.** A stated baseline or a set the user
added has no prescription behind it.

**Prescriptions are permanent.** The prescribed-versus-performed comparison *is*
the coaching signal, so a trained plan is never deleted and nothing may offer to
clear one.

**Nothing aggregated is stored.** Set count, top set, volume, estimated 1RM and
rest taken are computed from `PerformedSet`. Rest taken is the gap between
`completedAt` timestamps, which is truer than what a timer counted.

**A superset needs no extra structure.** Members share a `groupOrdinal`; round
*N* is the *N*th working set of each member, ordered by `order`; warm-ups precede
the group; rest falls out per exercise — `0` after the first member, the round's
rest after the last.

### Where a plan enters

**`PlanImporter` is the only seam, and it maps the document to the store
directly.** There is no intermediate value type: `PlanDocument` is already a
tree of plain values, and a second plain-value description of the same
prescription is a third vocabulary — the shape this project has paid a rewrite
to remove once. `PlanImporter` records what it was handed and never clamps,
floors, caps or defaults a prescribed value.

**A plan already in the store is merged, not ignored**, which is what lets the
coach write a week at a time. He may rewrite any block nothing has been logged
against and may not touch one that has — a set the user ticked is the record of
what happened, and a plan that rewrites it is refused by ordinal with nothing
taken in.

**The way back out is the document itself.** `PlanDocument(reconstructing:)`
reads stored sessions into the document they were imported as, and
`SnapshotExporter` sends that rather than a second description. The round-trip
suite is what says the store holds everything the document stated. Do not add a
third: a type that restates a prescription for a reader is the shape this cost a
rewrite to remove.

### The catalog

`Catalog/` holds bundled reference data, never SwiftData: it ships inside the
package, is never written at runtime, and every file carries a `version`. It
resolves through `Bundle.module`, not the app bundle. A resource that fails to
resolve does not look like an error — it looks like an empty catalog — so
`CatalogIntegrityTests` asserts the files load rather than trusting the build to
have copied them.

Exercise identity is the MoveKit slug (`docs/reference/movekit-exercise-slugs.txt`),
so purchased animations drop in without a mapping layer. Conditioning entries
carry our own IDs and simply have no animation.

**Nothing about a lift is copied into the store.** The database holds
`exerciseID` and nothing else about the movement; a working max is computed, and
*how he does a lift* is prose in `ACCOUNT.md`.

## Standards

These are binding. Code that violates them is not done.

**Errors are handled or propagated, never discarded.** No `try?` that drops an
error. A failed save must surface to the user — with CloudKit sync, save
conflicts are expected, not exceptional.

**No force unwrapping, force try, or force casting** outside tests. If a value
is guaranteed present, express that in the type.

**Data over code.** Facts about training live in versioned JSON or in the
coach's markdown, not in `switch` statements. No numeric literal expressing a
training opinion appears anywhere in Swift, including as a `static let` or a
default on a stored property.

**Record what you are given.** A prescribed value is stored exactly as
prescribed. No clamping a set count, no capping rest, no substituting a default
target, no seeding a load from a rule. If a value is missing, model its absence
honestly or refuse — never invent one.

**A set is counted, held, or carried, and no two of them are the same number.**
`Target` says which, read once at the document boundary and never re-guessed.
`WorkMeasure` gives the single answer everything binds to — one value with three
cases, never a set of booleans that could say two things at once. A performed set
carries `reps`, `durationSeconds` and `distance` as separate fields, and which
one a row writes is decided by what was prescribed, never by what was typed.
Nothing may add seconds or metres into a rep total. A distance keeps the unit it
was prescribed in and is never converted, exactly as `Mass` keeps its own. A hold
that was not timed and a carry that did not happen are `nil`, never zero.

Adding a fourth measure means adding a case to `WorkMeasure`, which will not
compile until every place that logs one has been told what to do with it.

**Refuse rather than discard.** An inbound document stating a key this format
does not have is refused with the key named and nothing taken in — never read
around. A silently dropped key tells the writer his prescription landed when none
of it did, which is the only failure here that reports success. `DocumentRefusal`
lives in LiftingKit so the phone and the server cannot answer it differently.

**Every inbound format is versioned, and skew is refused, not guessed.** A
reader refuses a newer document *whole*, naming both versions, before holding any
key against it — an unknown key is exactly what a later format is made of. Bump
the version when a reader would have to behave differently, never for an additive
field.

**Data earns its place or it goes.** A stored field, a document key, a catalog
column exists because something reads it and someone is better off for that. When
nothing does, it is removed — the property, its tests, its mention in every doc
comment — rather than left in place because it is cheap. Ask what reads it and
who is worse off without it; if the answer is nothing and nobody, remove it
completely.

**An icon does one of three jobs, or it does not exist.** Either it *names an
action* where a word will not fit, or it *marks a state that varies* within a
list where the variation is the information, or it is *a mark Claude chose* from
a closed set the app publishes and refuses anything outside. Anything else is
decoration.

The app must never pick one: a glyph inferred from `Push` is the app deciding
what a session trains from words it does not control. `SessionIcon.all` is the
vocabulary, `write_plan` offers it, `PlanImporter` refuses a name this build
cannot draw, and a day he marked nothing carries nothing. Which system symbol a
name draws as lives in `SessionIconView` and nowhere else.

**An icon identical everywhere it appears distinguishes nothing** — and its
pair, **an icon that varies must vary along one axis.**

**SF Symbols only, and no third-party set.** They match the system's optical
weight, scale with Dynamic Type, and follow the appearance. There is no icon set
that meaningfully covers 412 movements, so per-exercise glyphs would be guesswork
about what a lift *is*.

**Design tokens live in three files, and component metrics live with their
component.** `Palette` holds every colour, `Typography` the type roles, `Layout`
the spacing, radii and tap targets. A constant used by exactly one component
lives beside it — `SetTableMetrics` sat four hundred lines from the row that read
it, and was behind two defects in one week.

**Extensible taxonomies, not closed enums.** Muscle groups, equipment, movement
patterns and categories are raw-value-backed structs with static constants.
Unknown values from data must round-trip intact rather than crash or be dropped.

**Protocol seams at boundaries.** Layers depend on protocols, not concrete types.

**Tests before implementation.** The pure layers carry real coverage. Unit
conversion, the typed `Target`, and the two refusals — an `ExerciseID` the
catalog lacks, a document key this format does not have — are the highest-value
suites in the project, because they are the guard on data integrity.

**Every public type answers three questions** in its doc comment: what it does,
how it is used, what it depends on. If a type cannot be understood without
reading its internals, the boundary is wrong.

**Two people, and they have one name each.** The person holding the phone is
the **user**. The AI writing the plans is the **coach**. *User* is not a word
this project uses — not in a doc comment, not in a type name, not on screen —
because a codebase with two words for the same person invites a third. `Session`
is a workout, a `block` is a phase, `ACCOUNT.md` is the person and `PROGRAM.md`
is the routine.

**Copy is sentence case, everywhere, with one standard.** Buttons, menu items,
alert titles, navigation titles, empty states: *Add warm-up set*, not *Add Warmup
Set*; *Couldn't read what arrived*, not *Couldn't Read What Arrived*. Only the
app's own name is capitalised. This is Apple's rule and it is not a preference —
mixed casing on one screen reads as two authors.

**What is absent must be a thing.** An empty state names a missing *object* —
*No plan yet* — because a mass noun cannot be counted or absent: there is no such
object as *a training*, so *No training yet* never says what is missing. The
heading is the fact and the line under it is the one action.

A label names its control in the words the user would use, and **an action keeps
the same name through the whole flow**: the button that says *Finish workout*
produces a screen that says the workout is finished. A section heading is a plain
noun phrase — no article, no pronoun, no sentence.

**An error names what happened and what to do, in that order, and stops.** It
does not apologise, restate itself, or explain the format to somebody who cannot
act on it. A refusal written for the coach is relayed to the user verbatim
underneath one line of his own, because relaying it *is* the fix.

**Warnings are errors.** Swift 6 language mode, strict concurrency.

**Files stay focused.** A file past roughly 300 lines is doing too much.

## Verification

**Render everything a change touches.** A screenshot of the screen being worked
on is verification of that screen and nothing else. Four defects in one sprint
were siblings of a screen that had been rendered. When a shared modifier, token
or shape changes, list its callers and look at each one. A component with two
callers has two screenshots owing. `docs/rendering-the-app.md` holds the
scaffolding and the nine things that each cost an hour.

**Never claim work is complete without running the command and reading the
output.** State what was run and what it printed. If tests fail, say so.

**Reading test output correctly.** Every test here uses Swift Testing, so
`xcodebuild test` prints a legacy line that looks alarming and means nothing:

```
Test Suite 'All tests' passed. Executed 0 tests, with 0 failures
```

That is the XCTest reporter counting zero XCTest cases. The line that proves
tests ran is:

```
✔ Test run with 335 tests in 27 suites passed after 0.037 seconds.
```

`** TEST SUCCEEDED **` alone proves nothing — it prints even when nothing
executed. Always confirm the count:

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 \
  | grep -E "Test run with|✘|error:"
```
