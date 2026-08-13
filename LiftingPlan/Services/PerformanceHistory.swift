import Foundation

/// Bridges persisted `WorkoutPlan` data into the plain value types the
/// `ProgressionEngine` consumes. Keeps SwiftData out of the progression math.
enum PerformanceHistory {

    /// Most-recent logged performance for every exercise seen across `plans`
    /// (deduplicated by name, newest first).
    static func histories(from plans: [WorkoutPlan]) -> [ExerciseHistory] {
        let loggedExercises = plans
            .flatMap(\.sessions)
            .flatMap(\.exercises)
            .filter { !$0.completedWorkingSets.isEmpty }
            .sorted { latestLogDate($0) > latestLogDate($1) }

        var seen = Set<String>()
        var result: [ExerciseHistory] = []
        for exercise in loggedExercises {
            let key = exercise.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(history(from: exercise))
        }
        return result
    }

    /// The most recent logged history for one exercise name, optionally ignoring a
    /// specific in-progress exercise (so today's partial log doesn't shadow itself).
    static func latestHistory(
        forExerciseNamed name: String,
        excluding excluded: PlannedExercise?,
        from plans: [WorkoutPlan]
    ) -> ExerciseHistory? {
        let key = name.lowercased()
        let match = plans
            .flatMap(\.sessions)
            .flatMap(\.exercises)
            .filter { $0.name.lowercased() == key && !$0.completedWorkingSets.isEmpty && $0 !== excluded }
            .sorted { latestLogDate($0) > latestLogDate($1) }
            .first
        return match.map(history(from:))
    }

    static func history(from exercise: PlannedExercise) -> ExerciseHistory {
        let records = exercise.completedWorkingSets.map {
            SetRecord(weight: $0.weight, reps: $0.reps, rpe: $0.rpe)
        }
        return ExerciseHistory(
            name: exercise.name,
            repTargetUpper: exercise.repTargetUpperBound,
            recentSets: records
        )
    }

    private static func latestLogDate(_ exercise: PlannedExercise) -> Date {
        exercise.completedWorkingSets.map(\.completedAt).max() ?? .distantPast
    }
}
