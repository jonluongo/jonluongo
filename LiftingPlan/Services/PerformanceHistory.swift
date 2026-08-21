import Foundation
import SwiftData
import LiftingKit

/// One performed set, reduced to a plain value with no SwiftData attached.
///
/// **Why it is not the model.** A `PerformedSet` belongs to a `ModelContext` and
/// carries a graph behind it; a row that only has to *draw* what was lifted last
/// time should not hold one. Every measure is optional here for the same reason
/// it is on the model: `nil` is *he did not say*, and a number is *he did that
/// much*.
struct SetRecord: Equatable {
    var load: Mass?
    var reps: Int?
    var durationSeconds: Int?
    var distance: Distance?
}

/// What a movement's last time looked like.
///
/// **The grain is a performance, not a set.** *How did bench go last time* is
/// one answer with several sets in it, which is what `PerformedExercise` was
/// added to the store to say. Reading it as a flat run of sets meant every
/// caller regrouping them by date first.
struct ExerciseHistory: Equatable {
    var exerciseID: ExerciseID
    var occurredAt: Date
    /// The working sets, in order. Warm-ups are left out here rather than
    /// filtered by each caller: *what did he lift last time* is a question about
    /// work, and a warm-up in the answer reads as a lighter session.
    var sets: [SetRecord]
}

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
    ) throws -> ExerciseHistory? {
        try performances(of: exerciseID, in: context)
            .last { $0.occurredAt < moment }
    }

    /// Every performance of a movement, oldest first — what a coach means by
    /// *how has this lift gone*.
    ///
    /// A stated baseline is included and sits at the date it was said to have
    /// happened: he did it, nobody watched, and leaving it out would report a
    /// lifter starting from nothing.
    static func performances(
        of exerciseID: ExerciseID, in context: ModelContext
    ) throws -> [ExerciseHistory] {
        try context.fetch(FetchDescriptor<PerformedExercise>())
            .filter { $0.exerciseID == exerciseID }
            .sorted { $0.occurredAt < $1.occurredAt }
            .map(history(of:))
    }

    /// Every movement that has ever been performed, each once.
    static func everyExerciseTrained(in context: ModelContext) throws -> [ExerciseID] {
        let performed = try context.fetch(FetchDescriptor<PerformedExercise>())
        return Array(Set(performed.map(\.exerciseID))).sorted { $0.rawValue < $1.rawValue }
    }

    /// One stored performance as a plain value.
    static func history(of performed: PerformedExercise) -> ExerciseHistory {
        ExerciseHistory(
            exerciseID: performed.exerciseID,
            occurredAt: performed.occurredAt,
            sets: performed.workingSets.map(record(of:)))
    }

    private static func record(of set: PerformedSet) -> SetRecord {
        SetRecord(
            load: set.load, reps: set.reps,
            durationSeconds: set.durationSeconds, distance: set.distance)
    }
}
