import Foundation
import SwiftData
import LiftingKit

/// What the lifter can currently do on a given exercise.
///
/// A first plan has no logged history to progress from, so it needs a
/// starting point supplied up front rather than discovered by trial — this is
/// that starting point. `load` is `nil` for a bodyweight baseline rather than
/// zero, the same convention `LoggedSet.load` uses, so "no external weight"
/// and "an empty bar" stay distinguishable.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `ExerciseID` and `Mass` from Domain.
@Model
final class StrengthBaseline {
    var exerciseID: ExerciseID = ExerciseID(rawValue: "")
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    var load: Mass?
    var reps: Int = 0
    var recordedAt: Date = Date()

    init(
        exerciseID: ExerciseID = ExerciseID(rawValue: ""), load: Mass? = nil,
        reps: Int = 0, recordedAt: Date = Date()
    ) {
        self.exerciseID = exerciseID
        self.load = load
        self.reps = reps
        self.recordedAt = recordedAt
    }
}
