import Foundation

/// Bridges persisted `TrainingPlan` data into the plain value types the
/// `ProgressionEngine` consumes. Keeps SwiftData out of the progression math.
///
/// Every lookup here is keyed by `ExerciseID`, never by display name. Two
/// exercises that read as the same movement to a person — an AI-generated
/// "Bench Press (Barbell)" one week and the catalog's "Barbell Bench Press"
/// the next — must already share an `exerciseID` by the time they reach this
/// type, or their history silently fragments and progression resets. That
/// resolution happens upstream (`ExerciseResolver`); this type only ever joins
/// on the id it's handed.
///
/// Depends on: `TrainingPlan`/`TrainingWeek`/`WorkoutDay`/`PlannedExercise`
/// from Store, `ExerciseID`/`RepRange` from Domain, `ExerciseHistory`/`SetRecord`
/// from `ProgressionEngine.swift`.
enum PerformanceHistory {

    /// Most-recent logged performance for every exercise seen across `plans`
    /// (deduplicated by exercise id, newest first).
    static func histories(from plans: [TrainingPlan]) -> [ExerciseHistory] {
        let loggedExercises = allExercises(in: plans)
            .filter { !$0.completedWorkingSets.isEmpty }
            .sorted { latestLogDate($0) > latestLogDate($1) }

        var seen = Set<ExerciseID>()
        var result: [ExerciseHistory] = []
        for exercise in loggedExercises {
            guard !seen.contains(exercise.exerciseID) else { continue }
            seen.insert(exercise.exerciseID)
            result.append(history(from: exercise))
        }
        return result
    }

    /// The most recent logged history for one exercise, optionally ignoring a
    /// specific in-progress exercise (so today's partial log doesn't shadow itself).
    static func latestHistory(
        for exerciseID: ExerciseID,
        excluding excluded: PlannedExercise?,
        from plans: [TrainingPlan]
    ) -> ExerciseHistory? {
        let match = allExercises(in: plans)
            .filter { $0.exerciseID == exerciseID && !$0.completedWorkingSets.isEmpty && $0 !== excluded }
            .sorted { latestLogDate($0) > latestLogDate($1) }
            .first
        return match.map(history(from:))
    }

    static func history(from exercise: PlannedExercise) -> ExerciseHistory {
        let records = exercise.completedWorkingSets.map {
            SetRecord(load: $0.load, reps: $0.reps, rpe: $0.rpe)
        }
        return ExerciseHistory(
            exerciseID: exercise.exerciseID,
            displayName: exercise.displayName,
            repTargetUpper: RepRange(exercise.repRange).upperBound,
            recentSets: records
        )
    }

    /// Every exercise across the whole plan → week → day hierarchy. Walks the
    /// `orderedX` accessors rather than the raw relationship arrays — SwiftData
    /// does not guarantee relationship ordering, and callers here re-sort by
    /// log date anyway, but this keeps the traversal honest either way.
    ///
    /// This is the single hierarchy walk for logged-exercise data. `ExerciseTrend`
    /// (also in this layer) calls this rather than re-walking the tree itself —
    /// two independent traversals of the same relationship chain is exactly what
    /// let them drift before.
    static func allExercises(in plans: [TrainingPlan]) -> [PlannedExercise] {
        plans
            .flatMap(\.orderedWeeks)
            .flatMap(\.orderedDays)
            .flatMap(\.orderedExercises)
    }

    private static func latestLogDate(_ exercise: PlannedExercise) -> Date {
        exercise.completedWorkingSets.map(\.completedAt).max() ?? .distantPast
    }
}
