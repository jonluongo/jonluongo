import Foundation
import SwiftData
import LiftingKit

/// One set of a prescription whose sets differ, as the plan wrote it.
///
/// **What it does.** Holds a single set's own reps, load, effort target and
/// note, so a drop set, a ramp or a back-off set survives into the store as the
/// sets it actually is rather than as one averaged prescription.
///
/// **How it is used.** Only present when the plan listed its sets one at a
/// time; a plan that prescribed the same work throughout stores no rows at all
/// and states the count on `PlannedExercise.targetSets`. Never read these rows
/// directly to render or report — read `PlannedExercise.prescribedSets`, which
/// puts a set's own statements together with the exercise's.
///
/// **What it depends on.** `Mass` and `IntensityTarget` from LiftingKit. Every
/// value is `nil` when this set did not state one, which is not an absence of
/// prescription: the exercise's own value applies.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PrescribedSet {
    /// Position within the exercise, ascending. The order the sets are to be
    /// done in, which for a ramp or a drop set is the whole prescription.
    var order: Int = 0
    /// This set's rep target as written. `nil` to use the exercise's.
    var repRange: String?
    /// This set's load, in the unit it was written in. `nil` to use the
    /// exercise's.
    var suggestedLoad: Mass?
    /// How hard this set should be. `nil` to use the exercise's.
    var intensity: IntensityTarget?
    /// Anything about this set alone, such as "last set to failure".
    var notes: String?

    var exercise: PlannedExercise?

    init(
        order: Int = 0, repRange: String? = nil, suggestedLoad: Mass? = nil,
        intensity: IntensityTarget? = nil, notes: String? = nil
    ) {
        self.order = order
        self.repRange = repRange
        self.suggestedLoad = suggestedLoad
        self.intensity = intensity
        self.notes = notes
    }

    /// This row as the shared value type the document and the snapshot use, so
    /// one vocabulary describes a prescribed set everywhere.
    var prescription: SetPrescription {
        SetPrescription(
            repRange: repRange, suggestedLoad: suggestedLoad,
            intensity: intensity, notes: notes
        )
    }
}
