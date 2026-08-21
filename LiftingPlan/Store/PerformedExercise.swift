import Foundation
import SwiftData
import LiftingKit

/// One exercise, on one day, as it actually went.
///
/// **This is the grain the store never had.** *How has bench gone* is a series
/// of performances, not a series of sets — and `exercise_history` used to return
/// a flat array of sets with the plan, block, weekday and focus restated on
/// every row, because nothing in the store sat where the question is asked.
///
/// **It exists only if something happened.** No row is created when a screen is
/// opened. That is why there is no `isCompleted` anywhere in this store: the
/// row's existence is the fact.
///
/// **Its link to the prescription is nullable, and that is meaningful.** A set
/// the user added, and a baseline he stated in conversation, have no
/// prescription behind them. `source` says which of the two ways this came to be
/// known — a stated baseline is a performance with one set, not a second table
/// saying the same thing in the same shape.
///
/// **It never carries an aggregate.** Set count, top set, volume and estimated
/// 1RM are computed from the sets beneath it. A stored copy can disagree with
/// them, and this is the table where being wrong is worst.
///
/// **What it depends on.** `ExerciseID` and `PerformanceSource` from LiftingKit.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PerformedExercise {

    /// The catalog's identity for the movement performed. Carried here rather
    /// than read through the prescription, because a stated baseline has no
    /// prescription — and because a record that stops making sense when a plan
    /// is deleted is not a log.
    var exerciseID: ExerciseID = ExerciseID(rawValue: "")
    /// When this was performed. For a stated baseline, when he says he did it.
    var occurredAt: Date = Date()
    /// What the user said about it, in his own words. `nil` when he said
    /// nothing.
    ///
    /// It lives on the record rather than on the prescription because it is
    /// his: a note on a `PlannedExercise` would be governed by the coach's
    /// rewrite rules, and a note on a session neither finished nor logged would
    /// go when the coach rewrote the block.
    var userNote: String?
    /// How this came to be known — ticked in the app, or told to the coach.
    private var sourceRawValue: String = PerformanceSource.logged.rawValue

    var session: Session?
    /// What was prescribed for this, or `nil` for a set the user added and for
    /// a baseline he stated.
    var planned: PlannedExercise?

    @Relationship(deleteRule: .cascade, inverse: \PerformedSet.exercise)
    var sets: [PerformedSet]? = []

    init(
        exerciseID: ExerciseID = ExerciseID(rawValue: ""), occurredAt: Date = Date(),
        userNote: String? = nil, source: PerformanceSource = .logged
    ) {
        self.exerciseID = exerciseID
        self.occurredAt = occurredAt
        self.userNote = userNote
        self.sourceRawValue = source.rawValue
    }

    /// How this came to be known. An unreadable stored value reads as `.logged`,
    /// which is the answer that claims least.
    var source: PerformanceSource {
        get { PerformanceSource(rawValue: sourceRawValue) ?? .logged }
        set { sourceRawValue = newValue.rawValue }
    }

    /// The sets performed, in the order they happened.
    var orderedSets: [PerformedSet] {
        (sets ?? []).sorted { $0.completedAt < $1.completedAt }
    }

    /// The working sets, in order — what progression is read from.
    var workingSets: [PerformedSet] { orderedSets.filter { !$0.isWarmup } }
}
