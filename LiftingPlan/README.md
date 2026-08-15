# LiftingPlan

An iOS app for training seriously: it holds the exercise catalog, records what
you were prescribed, paces your rest between sets with automatic timers, logs
every set you lift, and shows you what your lifts are doing over time.

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
simulator or device. No dependencies to fetch — the project uses only Apple
frameworks (SwiftUI, SwiftData, Charts, UserNotifications).

## Architecture

Four layers, importing only downward: `Domain/` → `Catalog/` → `Store/` →
`Services/` → `Views/`. See the root `CLAUDE.md` for the binding version.

- **`LiftingPlanApp`** — app entry, SwiftData container, the bundled catalog,
  and the shared `RestTimerModel`.
- **`Domain/`** — pure value types: `Mass`, `RepRange`, `Exercise`, the
  taxonomies. Foundation only.
- **`Catalog/`** — `ExerciseCatalog` (the lego box and the query surface) and
  `ExerciseResolver` (free text → a real `ExerciseID`).
- **`Store/`** — SwiftData `@Model` types: `UserProfile`, `TrainingPlan`,
  `TrainingWeek`, `WorkoutDay`, `PlannedExercise`, `LoggedSet`,
  `StrengthBaseline`, `BodyMetric`.
- **`Services/`**
  - `PlanBlueprint` — plain-value plan representation and the single mapping
    into SwiftData, which records what it is handed without alteration.
  - `PerformanceHistory` — the one hierarchy traversal; joins logs on
    `ExerciseID`.
  - `ExerciseTrend` — per-exercise top-set and estimated-1RM series.
  - `RestTimerModel` — the date-based pace timer.
- **`Views/`** — `SetupView`, `PlanOverviewView`, `SessionDetailView`,
  `ActiveWorkoutView`, `HistoryView`, `SettingsView`, plus small components.

`Catalog/Resources/assembly-rules.json` is inert reference material for Claude.
No Swift code decodes it, by design.

## Tests

Swift Testing suites cover the pure layers — the exercise resolver, unit
conversion, catalog integrity, blueprint mapping, trends, and rest-timer math.
Run with `⌘U`.
