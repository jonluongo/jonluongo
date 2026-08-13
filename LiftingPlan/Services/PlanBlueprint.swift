import Foundation

/// A plain-value description of a generated plan. Both the on-device model path
/// and the deterministic fallback produce one of these, and it is the single
/// thing we map into SwiftData — which keeps that mapping easy to unit-test.
struct PlanBlueprint: Equatable {
    var days: [DayBlueprint]
}

struct DayBlueprint: Equatable {
    var weekday: Weekday
    var focus: String
    var durationMinutes: Int
    var exercises: [ExerciseBlueprint]
}

struct ExerciseBlueprint: Equatable {
    var name: String
    var muscleGroup: String
    var repRange: String
    var sets: Int
    var restSeconds: Int
    var suggestedWeight: Double?
    var tempo: String?
    var notes: String?
}

extension PlanBlueprint {
    /// Build the SwiftData object graph for this blueprint. Values are clamped to
    /// sane ranges so a stray model output can never produce a nonsensical plan.
    func makeWorkoutPlan(goal: String, durationMinutes: Int, wasModelGenerated: Bool) -> WorkoutPlan {
        let plan = WorkoutPlan(
            goalSnapshot: goal,
            durationMinutes: durationMinutes,
            wasModelGenerated: wasModelGenerated
        )
        plan.sessions = days.enumerated().map { dayIndex, day in
            let session = WorkoutSession(
                weekday: day.weekday,
                focus: day.focus.isEmpty ? "Training" : day.focus,
                targetDurationMinutes: max(10, day.durationMinutes),
                order: dayIndex
            )
            session.exercises = day.exercises.enumerated().map { exIndex, ex in
                PlannedExercise(
                    name: ex.name,
                    muscleGroup: ex.muscleGroup,
                    order: exIndex,
                    targetSets: min(max(ex.sets, 1), 8),
                    repRange: ex.repRange.isEmpty ? "8-12" : ex.repRange,
                    suggestedWeight: ex.suggestedWeight,
                    restSeconds: min(max(ex.restSeconds, 15), 600),
                    tempo: ex.tempo,
                    notes: ex.notes
                )
            }
            return session
        }
        return plan
    }
}
