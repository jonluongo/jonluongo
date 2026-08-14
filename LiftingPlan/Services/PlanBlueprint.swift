import Foundation

/// A plain-value description of a generated plan. Both the on-device model path
/// and the deterministic fallback produce one of these, and it is the single
/// thing we map into SwiftData — which keeps that mapping easy to unit-test.
///
/// Produced by `PlanGenerator`/`TemplatePlanBuilder`, turned into a persisted
/// `TrainingPlan` by `makeWorkoutPlan(goal:durationMinutes:wasModelGenerated:)`
/// below. Depends on: `DayBlueprint`.
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
    /// holding a single `TrainingWeek` (ordinal 1) whose days are these. Values
    /// are clamped to sane ranges so a stray model output can never produce a
    /// nonsensical plan.
    ///
    /// A `PlanBlueprint` only ever describes one week's worth of training, so
    /// this maps it into exactly one concrete week rather than inventing
    /// additional weeks; prescribing genuinely different work across a
    /// multi-week block (e.g. a deload) is out of scope here.
    func makeWorkoutPlan(goal: String, durationMinutes: Int, wasModelGenerated: Bool) -> TrainingPlan {
        let plan = TrainingPlan(
            goal: goal,
            weekCount: 1,
            durationMinutes: durationMinutes,
            wasModelGenerated: wasModelGenerated
        )
        let week = TrainingWeek(ordinal: 1)
        week.days = days.map { day in
            let workoutDay = WorkoutDay(
                weekday: day.weekday,
                focus: day.focus.isEmpty ? "Training" : day.focus,
                durationMinutes: max(10, day.durationMinutes)
            )
            workoutDay.exercises = day.exercises.enumerated().map { exIndex, ex in
                PlannedExercise(
                    exerciseID: ex.exerciseID,
                    displayName: ex.displayName,
                    order: exIndex,
                    targetSets: min(max(ex.sets, 1), 8),
                    repRange: ex.repRange.isEmpty ? "8-12" : ex.repRange,
                    suggestedLoad: ex.suggestedLoad,
                    restSeconds: min(max(ex.restSeconds, 15), 600),
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
