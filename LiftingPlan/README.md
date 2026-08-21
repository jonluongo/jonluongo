# Superset

An iOS app that turns casual lifting into progressively harder training.

**The app is two things: a datastore, and the interface an AI trainer works
through.** It owns the exercise catalog and the training log, displays plans, and
logs sets. Claude — reached over MCP — decides the split, the exercises, sets,
reps, rest, load, intensity, how a block progresses, and what changes after an
injury.

There is no plan generator and deliberately no fallback one. Until Claude writes
a plan, the app shows an empty state.

**The app asks the lifter nothing.** No onboarding, no setup screen, no settings
form for a training question. Days, session length, goal, equipment, experience
and injuries are things Claude asks better in conversation, and he writes them
into `ACCOUNT.md`. The one preference the app owns is whether the rest clock runs at
all — that is about this phone, not about the lifter, so it lives in
`UserDefaults` and never syncs.

**It records what it is given.** A prescribed value is stored exactly as
prescribed: never clamped, floored, capped, or defaulted. A document stating a
key this format does not have is refused whole, with the key named.

The Xcode project, the scheme, the bundle identifier and the iCloud container are
all still named `LiftingPlan`. Only the name on the Home Screen changed —
renaming an identifier would orphan the container and the data already on the
device.

## The loop

> The coach reads `ACCOUNT.md`, `PROGRAM.md` and the performed tables, and writes
> prescriptions. The app draws them and logs against them.

| File | Written by | Read by |
|---|---|---|
| `snapshot.json` | phone | server |
| `plan.json` | server | phone |
| `ACCOUNT.md`, `PROGRAM.md` | server | phone, **rendered, never parsed** |

The files pass through a shared iCloud folder. **The phone is the only writer of
the record**, so a reliable export is always current: it exports on Finish,
debounced after any logged set, and on backgrounding under a background-task
assertion.

**The plan archive is designed and not built.** `CLAUDE.md` and `docs/decided.md`
both describe `plans/<id>.json` — one file kept per import, never mutated, named
by its ID — so that every prescription the coach ever wrote survives in the form
he wrote it. Nothing writes it today, which means `Session.sourceDocumentID` is
stored and exported while pointing at nothing.

**Markdown is rendered and never parsed.** Nothing is read *out* of prose — the
moment a number must come out of a file, that number belongs in a table. Writes
to it are anchored edits (`{file, oldText, newText}`), refused whole if the
anchor is missing or ambiguous.

## What is in the repository

| Path | What it is |
|---|---|
| `LiftingPlan/` | the iOS app |
| `LiftingKit/` | the shared package — the vocabulary the phone and the server cannot disagree about |
| `LiftingMCP/` | the macOS MCP server Claude talks to |

## Requirements

- Xcode 26+
- iOS 26.0+ deployment target

## Build & run

Open `LiftingPlan.xcodeproj` and run the `LiftingPlan` scheme. The only
dependencies are the two local packages in this repository; everything else is an
Apple framework (SwiftUI, SwiftData, Charts, UserNotifications).

## Architecture

**A layer may import only the layers above it.** This is the most important rule
in the project; `CLAUDE.md` holds the binding version of it.

| Layer | Where | What is in it |
|---|---|---|
| `Domain/` | LiftingKit | pure value types — `Mass`, `Target`, `Exercise`, the taxonomies. Foundation only. |
| `Catalog/` | LiftingKit | `exercises.json` and the query surface over it. Bundled, versioned, never written at runtime. |
| `Documents/` | LiftingKit | the wire formats and their refusals — `PlanDocument`, `TrainingSnapshot`, `DocumentRefusal`. |
| `Transport/` | LiftingKit | the shared-folder protocol and the two markdown files. |
| `Store/` | app | SwiftData models. User data only. |
| `Services/` | app | queries over stored data, timing, and the one mapping into the store. |
| `Presentation/` | app | pure logic turning models into what a screen states. **No SwiftUI.** |
| `Views/` | app | SwiftUI, and nothing else. |

`Domain/` importing nothing but Foundation is what makes the interesting logic
testable without a database, simulator, or model.

**`Store/` deliberately stays in the app.** The server reads a snapshot file and
must never link SwiftData.

**If it does not import SwiftUI, it does not live in `Views/`.** A type that
turns a prescription into `"3 × 6-8 · 80% effort"` holds no state and draws
nothing, and is worth testing against strings — that is what `Presentation/` is.

### The store — five tables

```
Session
  PlannedExercise   →   PerformedExercise
    PlannedSet      →     PerformedSet
```

**Intent and event never share a table.** That one rule produces the rest.

- **`Session`** has no date: *when* he trained is a fact about the record.
- **Blocks are ordinals and have no names.** What makes block 3 an accumulation
  block is a line in `PROGRAM.md`.
- **Every prescribed set is a row**, so a ramp, a drop set and three identical
  sets are one shape.
- **A performed row exists only if it happened.** There is no `isCompleted` — the
  row's existence is the fact.
- **Prescriptions are permanent.** The prescribed-versus-performed comparison
  *is* the coaching signal, so a trained plan is never deleted.
- **Nothing aggregated is stored.** Set count, top set and volume are computed.

`PlanImporter` is the only way a plan enters, and `PlanDocument(reconstructing:)`
is the way back out — the round-trip suite is what says the store holds
everything the document stated.

### The catalog

412 movements, keyed by MoveKit slug so purchased animations drop in without a
mapping layer. **Nothing about a lift is copied into the store** — the database
holds `exerciseID` and nothing else about the movement.

Free text never becomes an `ExerciseID`. `list_exercises` offers candidates and
the coach sends one back verbatim; an ID the catalog lacks is refused. A
fabricated key fragments a lift's history irreparably, which is the one thing
this app insists on.

## Tests

**All three suites must be run** — the app suite covers neither the catalog, the
taxonomies, the document formats, nor the MCP tools.

```sh
xcodebuild -project LiftingPlan.xcodeproj -scheme LiftingPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
swift test --package-path LiftingKit
swift test --package-path LiftingMCP
```

Xcode compiles a package dependency with `-suppress-warnings`, so the standard is
enforced on the packages explicitly:

```sh
swift build --package-path LiftingKit -Xswiftc -warnings-as-errors
swift build --package-path LiftingMCP -Xswiftc -warnings-as-errors
```

Every suite uses **Swift Testing**, so `xcodebuild` prints a legacy
`Executed 0 tests` line that means nothing. The line that proves tests ran is
`✔ Test run with N tests in M suites passed`, and `** TEST SUCCEEDED **` alone
proves nothing.

## Further reading

- `CLAUDE.md` — the binding architecture and standards.
- `docs/decided.md` — what was tried and rejected, and why. Read it before
  proposing anything; confidently re-proposing a rejected idea is the predictable
  failure of a long session.
- `docs/rendering-the-app.md` — how to get a screen on screen, and the nine
  things that each cost an hour.
