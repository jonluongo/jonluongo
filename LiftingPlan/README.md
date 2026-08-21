# Barbell

An iOS app for training seriously: it holds the exercise catalog, records what
you were prescribed, paces your rest between sets with automatic timers, logs
every set you lift, and shows you what your lifts are doing over time.

The Xcode project, the scheme, the bundle identifier and the iCloud container
are all still named `LiftingPlan`. Only the name on the Home Screen changed —
renaming an identifier would orphan the container and the data already on the
device.

**The app makes no training decisions.** It is the legos, the record, and the
interface. Claude does the planning — over MCP — and the app stores whatever
plan it is given, recorded exactly as given. It never clamps, floors, caps, or
substitutes a prescribed value. Before a plan exists, it shows an empty state.

## Highlights

- **Setup in three inputs** — pick training days, session duration, and type a goal.
- **A 412-exercise catalog** keyed by MoveKit slug, queryable by name, muscle,
  equipment, pattern, and substitutability — bundled, versioned, never written
  at runtime.
- **Pace timers** — a rest countdown starts automatically the moment you log a
  set, with a progress ring, haptics, a sound, and a background local
  notification so the cue lands even with the screen locked. Optional per-rep
  tempo cues (e.g. `3-0-1-0`) are shown per exercise.
- **Spreadsheet-style logging** — every exercise in one scroll, each with an
  editable table of sets (`SET · PREVIOUS · LBS · REPS · ✓`). The **PREVIOUS**
  column shows last time's numbers, warmup rows are marked **W**, checking a set
  off tints it green and kicks off the rest timer. Persisted with **SwiftData**.
- **Previous performance, as reference** — the log shows what you did last time
  next to what you were prescribed. It shows both; it substitutes neither.
- **Progress view** — per-exercise strength trends (estimated 1RM) with Swift Charts.

## Requirements

- Xcode 26+
- iOS 26.0+ deployment target

## Build & run

Open `LiftingPlan.xcodeproj` in Xcode and run the `LiftingPlan` scheme on a
simulator or device. The only dependency is the local `LiftingKit` package in
this repository; everything else is an Apple framework (SwiftUI, SwiftData,
Charts, UserNotifications).

## Architecture

Four layers, importing only downward: `Domain/` → `Catalog/` → `Store/` →
`Services/` → `Views/`. See the root `CLAUDE.md` for the binding version.

The first two layers live in the local package `LiftingKit/`, not in the app
target. They are the shared vocabulary — what an exercise is, what a weight is,
what the catalog contains — so the app and the macOS MCP server cannot disagree
about any of it. `Store/` deliberately stays in the app: the server reads a
snapshot file and must never link SwiftData.

- **`LiftingPlanApp`** — app entry, SwiftData container, the bundled catalog,
  and the shared `RestTimerModel`.
- **`LiftingKit` → `Domain/`** — pure value types: `Mass`, `RepRange`,
  `Exercise`, the taxonomies. Foundation only.
- **`LiftingKit` → `Catalog/`** — `ExerciseCatalog`: the bundled reference data,
  and the query surface `list_exercises` searches. Free text never becomes an
  `ExerciseID` here — the catalog offers candidates and the coach sends one back
  verbatim.
- **`Store/`** — SwiftData `@Model` types: `UserProfile`, `TrainingPlan`,
  `TrainingWeek`, `WorkoutDay`, `PlannedExercise`, `LoggedSet`,
  `StrengthBaseline`, `BodyMetric`. **These keep their original names on
  purpose**: CloudKit derives its record types from the entity name, so renaming
  one orphans everything already synced. A `TrainingPlan` is what the app calls a
  *routine*, a `TrainingWeek` is a *block*, a `WorkoutDay` is a *session* — see
  `docs/decided.md`.
- **`Services/`**
  - `RoutineBlueprint` — plain-value routine representation and the single
    mapping into SwiftData, which records what it is handed without alteration.
  - `DocumentInbox` / `ProfileUpdater` — the inbound half of the loop: a plan
    and a profile update arrive in the shared folder, and this is what applies
    them. `ProfileUpdater` is the only way a fact about the lifter is stored.
  - `PerformanceHistory` — the one hierarchy traversal; joins logs on
    `ExerciseID`.
  - `ExerciseTrend` — per-exercise top-set and estimated-1RM series.
  - `RestTimerModel` — the date-based pace timer.
- **`Views/`** — `RootView`, `RoutinesView` (the list), `RoutineView` (one
  routine, its blocks and their sessions), `ActiveWorkoutView` (logging a
  session), `AccountView`, plus small components.
  There is deliberately no setup or onboarding view: the app asks the lifter
  nothing, and Account holds only the record and the delete.

`LiftingKit/Sources/LiftingKit/Catalog/Resources/assembly-rules.json` is inert
reference material for Claude. No Swift code decodes it, by design.

## Tests

Swift Testing suites cover the pure layers — the exercise resolver, unit
conversion, catalog integrity, blueprint mapping, trends, and rest-timer math.
They live in two places now: the package suites run with
`swift test --package-path LiftingKit`, and the app suites run with `⌘U`.
