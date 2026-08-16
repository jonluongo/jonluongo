import Foundation
import LiftingKit

/// One logged set, reduced to a plain value with no SwiftData attached.
///
/// Built from a `LoggedSet` by `PerformanceHistory`, and shown to the lifter as
/// what he did last time. A set is counted, held, or carried: `durationSeconds`
/// and `distance` are `nil` on a counted set, and `reps` is zero on either of
/// the others. Depends on: `Mass` and `Distance` from Domain.
struct SetRecord: Equatable {
    /// The weight as logged, in the unit it was logged in. `nil` means bodyweight.
    var load: Mass?
    var reps: Int
    /// How long it was held, in seconds. `nil` when it was counted or carried instead.
    var durationSeconds: Int?
    /// How far it was carried, in the unit it was carried in. `nil` when it was
    /// counted or held instead.
    var distance: Distance?
    var rpe: Double?
}

/// What the lifter most recently did on a single exercise.
///
/// Keyed by `exerciseID`, never by name — that stable identity is what lets a
/// lift's history survive a catalog rename or a later plan phrasing the same
/// movement differently. `displayName` is carried for display only; it must
/// never be compared or used as a key. Produced by `PerformanceHistory`, read
/// by the log and the history views. This is a record of what happened, not a
/// verdict about it. Depends on: `ExerciseID` from Domain, `SetRecord`.
struct ExerciseHistory: Equatable {
    var exerciseID: ExerciseID
    /// For display only — never compared or used as a key.
    var displayName: String
    /// Upper bound of the prescribed rep range (e.g. "8-12" -> 12).
    var repTargetUpper: Int
    /// Sets from the lifter's most recent session on this exercise, in order.
    var recentSets: [SetRecord]
}

/// Answers "what did he last do on this movement?" by walking the persisted
/// plan hierarchy and joining on `ExerciseID`. Keeps SwiftData out of the
/// value types above.
///
/// Every lookup here is keyed by `ExerciseID`, never by display name. Two
/// exercises that read as the same movement to a person — "Bench Press
/// (Barbell)" in one plan and the catalog's "Barbell Bench Press" in the next
/// — must already share an `exerciseID` by the time they reach this type, or
/// their history silently fragments and a lift's record is lost. That
/// resolution happens upstream (`ExerciseResolver`); this type only ever joins
/// on the id it's handed.
///
/// This is a query. It reports history; it draws no conclusion from it.
///
/// Depends on: `TrainingPlan`/`TrainingWeek`/`WorkoutDay`/`PlannedExercise`
/// from Store, `ExerciseID`/`RepRange` from Domain, `ExerciseHistory`/`SetRecord`
/// above.
enum PerformanceHistory {

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
            SetRecord(
                load: $0.load, reps: $0.reps, durationSeconds: $0.durationSeconds,
                distance: $0.distance, rpe: $0.rpe)
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
