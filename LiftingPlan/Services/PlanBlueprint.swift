import Foundation

/// A plain-value description of a plan the app has been handed.
///
/// This is the single thing that gets mapped into SwiftData, which keeps that
/// mapping easy to unit-test and leaves exactly one place where a plan can
/// enter the store. Turned into a persisted `TrainingPlan` by
/// `makeWorkoutPlan(goal:durationMinutes:catalogVersion:)` below. Depends on:
/// `DayBlueprint`.
struct PlanBlueprint: Equatable {
    var days: [DayBlueprint]
}

/// One training day within a `PlanBlueprint`. Depends on: `Weekday` from
/// Domain, `ExerciseBlueprint`.
struct DayBlueprint: Equatable {
    var weekday: Weekday
    var focus: String
    var durationMinutes: Int
    var exercises: [ExerciseBlueprint]
}

/// One prescribed movement within a `DayBlueprint`.
///
/// `exerciseID` is the identity that gets persisted onto `PlannedExercise` and
/// is what `PerformanceHistory` joins on; `displayName` is shown to the lifter
/// and carried through for display only. Never resolve or match an exercise by
/// `displayName` — collapsing that distinction back into a single free-text
/// name is exactly the bug this type's shape exists to prevent. Depends on:
/// `ExerciseID`, `Mass` from Domain.
struct ExerciseBlueprint: Equatable {
    var exerciseID: ExerciseID
    var displayName: String
    var repRange: String
    var sets: Int
    var restSeconds: Int
    var suggestedLoad: Mass?
    var tempo: String?
    var notes: String?
}

extension PlanBlueprint {
    /// Build the SwiftData object graph for this blueprint: a new `TrainingPlan`
    /// holding a single `TrainingWeek` (ordinal 1) whose days are these.
    ///
    /// **Every value is recorded exactly as given.** Nothing here clamps,
    /// floors, caps, or substitutes: 10 sets stay 10 sets, a 12-minute rest
    /// between heavy singles stays 12 minutes, and an unstated rep range stays
    /// unstated rather than becoming someone's idea of a sensible default.
    /// Whoever wrote the plan made those calls with more context than this
    /// function will ever have, and a silently altered prescription is
    /// indistinguishable from the one that was actually written.
    ///
    /// A `PlanBlueprint` only ever describes one week's worth of training, so
    /// this maps it into exactly one concrete week rather than inventing
    /// additional weeks; prescribing genuinely different work across a
    /// multi-week block (e.g. a deload) is out of scope here.
    ///
    /// `catalogVersion` is the `ExerciseCatalogProviding.version` these
    /// exercises were selected from; it is stamped onto the plan so a later
    /// correction to the catalog data can be detected rather than silently
    /// reinterpreting logged work. It has deliberately no default value — the
    /// stamp is only meaningful if every caller states where its exercises came
    /// from, so the compiler asks rather than a wrong value being assumed.
    func makeWorkoutPlan(
        goal: String,
        durationMinutes: Int,
        catalogVersion: Int
    ) -> TrainingPlan {
        let plan = TrainingPlan(
            goal: goal,
            weekCount: 1,
            durationMinutes: durationMinutes,
            catalogVersion: catalogVersion
        )
        let week = TrainingWeek(ordinal: 1)
        week.days = days.map { day in
            let workoutDay = WorkoutDay(
                weekday: day.weekday,
                focus: day.focus,
                durationMinutes: day.durationMinutes
            )
            workoutDay.exercises = day.exercises.enumerated().map { exIndex, ex in
                PlannedExercise(
                    exerciseID: ex.exerciseID,
                    displayName: ex.displayName,
                    order: exIndex,
                    targetSets: ex.sets,
                    repRange: ex.repRange,
                    suggestedLoad: ex.suggestedLoad,
                    restSeconds: ex.restSeconds,
                    tempo: ex.tempo,
                    notes: ex.notes
                )
            }
            return workoutDay
        }
        plan.weeks = [week]
        return plan
    }
}
