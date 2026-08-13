# LiftingPlan

An iOS app that turns casual lifting into progressively harder training. You tell
it which days you train, how long you have, and your goal — it builds a weekly
lifting plan, paces your rest between sets with automatic timers, logs your
weights, and pushes you to do more next time.

## Highlights

- **Setup in three inputs** — pick training days, session duration, and type a goal.
- **On-device plan generation** with Apple's **Foundation Models** framework
  (`@Generable` guided generation). No account, no API key, fully private. Falls
  back to built-in templates when Apple Intelligence isn't available, so the app
  works on any device or simulator.
- **Pace timers** — a rest countdown starts automatically the moment you log a
  set, with a progress ring, haptics, a sound, and a background local
  notification so the cue lands even with the screen locked. Optional per-rep
  tempo cues (e.g. `3-0-1-0`) are shown per exercise.
- **Weight logging** — record weight, reps, and optional RPE for every set,
  persisted with **SwiftData**.
- **Progressive overload** — a pure, unit-tested `ProgressionEngine` reads your
  recent performance and recommends the next target (add load when reps are met
  at a manageable effort, hold when it was a grind). That summary is fed back to
  the model on regeneration so plans keep ratcheting up intensity.
- **Progress view** — per-exercise strength trends (estimated 1RM) with Swift Charts.

## Requirements

- Xcode 26+
- iOS 26.0+ deployment target
- Apple Intelligence–capable device for on-device AI generation (otherwise the
  template engine is used automatically)

## Build & run

Open `LiftingPlan.xcodeproj` in Xcode and run the `LiftingPlan` scheme on a
simulator or device. No dependencies to fetch — the project uses only Apple
frameworks (SwiftUI, SwiftData, FoundationModels, Charts, UserNotifications).

## Architecture

- **`LiftingPlanApp`** — app entry, SwiftData container, shared `PlanGenerator`
  and `RestTimerModel`.
- **`Models/`** — SwiftData `@Model` types: `TrainingPreferences`, `WorkoutPlan`,
  `WorkoutSession`, `PlannedExercise`, `SetLog`.
- **`Services/`**
  - `PlanGenerator` — Foundation Models wrapper + guided-generation schema, with
    availability checks and a template fallback.
  - `TemplatePlanBuilder` — deterministic plan generator.
  - `PlanBlueprint` — plain-value plan representation and the single mapping into
    SwiftData.
  - `ProgressionEngine` — pure progression logic (the "push me" brain).
  - `PerformanceHistory` — bridges persisted logs into the engine's value types.
  - `RestTimerModel` — the date-based pace timer.
  - `PlanCoordinator` — ties generation + persistence together.
- **`Views/`** — `SetupView`, `PlanOverviewView`, `SessionDetailView`,
  `ActiveWorkoutView`, `HistoryView`, `SettingsView`, plus small components.

## Tests

Swift Testing suites cover the pure logic — progression decisions, blueprint
mapping/clamping, the template builder, and rest-timer math. Run with `⌘U`.
