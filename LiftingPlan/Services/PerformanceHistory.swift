import Foundation
import SwiftData
import LiftingKit

/// What has been performed, answered from the store.
///
/// **What it does.** Reports the last time a movement was trained, and every
/// time it has been. It reports and never concludes: whether a lift is
/// progressing, stalling or worth changing is the coach's to say.
///
/// **It fetches rather than walking relationships.** A relationship read returns
/// whatever the context happens to have faulted in, which is how a report can
/// silently describe part of the record as though it were all of it.
///
/// **What it depends on.** The `Store/` models and a `ModelContext`.
enum PerformanceHistory {

    /// The most recent performance of a movement, or `nil` if it has never been
    /// trained.
    ///
    /// `before` is exclusive, so a set row asking what happened *last* time does
    /// not get the session it is currently in.
    static func mostRecent(
        _ exerciseID: ExerciseID, before moment: Date = .distantFuture,
        in context: ModelContext
    ) throws -> SnapshotPerformedExercise? {
        try performances(of: exerciseID, in: context)
            .last { $0.occurredAt < moment }
    }

    /// Every performance of a movement, oldest first — what a coach means by
    /// *how has this lift gone*.
    ///
    /// A stated baseline is included and sits at the date it was said to have
    /// happened: he did it, nobody watched, and leaving it out would report a
    /// user starting from nothing.
    static func performances(
        of exerciseID: ExerciseID, in context: ModelContext
    ) throws -> [SnapshotPerformedExercise] {
        try context.fetch(FetchDescriptor<PerformedExercise>())
            .filter { $0.exerciseID == exerciseID }
            .sorted { $0.occurredAt < $1.occurredAt }
            .map(value(of:))
    }

    /// Every movement that has ever been performed, each once.
    static func everyExerciseTrained(in context: ModelContext) throws -> [ExerciseID] {
        let performed = try context.fetch(FetchDescriptor<PerformedExercise>())
        return Array(Set(performed.map(\.exerciseID))).sorted { $0.rawValue < $1.rawValue }
    }

    /// One stored performance as plain values.
    ///
    /// **The value type is the wire's, not a third one.** `SnapshotPerformedExercise`
    /// already *is* the plain-value form of a performed exercise, exactly as
    /// `PlanDocumentSession` is for a prescription — and a screen and a coach
    /// asking the same question deserve the same answer. A private `SetRecord`
    /// here was a second shape for one idea, and it carried a word this domain
    /// has already spoken for: to a user, a record is a PR.
    static func value(of performed: PerformedExercise) -> SnapshotPerformedExercise {
        SnapshotPerformedExercise(
            exerciseID: performed.exerciseID,
            occurredAt: performed.occurredAt,
            source: performed.source,
            blockOrdinal: performed.session?.blockOrdinal,
            sessionOrdinal: performed.session?.ordinal,
            userNote: performed.userNote,
            sets: performed.orderedSets.map(value(of:)))
    }

    private static func value(of set: PerformedSet) -> SnapshotPerformedSet {
        SnapshotPerformedSet(
            setIndex: set.setIndex, isWarmup: set.isWarmup, load: set.load,
            reps: set.reps, durationSeconds: set.durationSeconds,
            distance: set.distance, completedAt: set.completedAt)
    }
}
