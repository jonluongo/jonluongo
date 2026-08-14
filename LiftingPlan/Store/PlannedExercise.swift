import Foundation
import SwiftData

/// A prescribed movement within a day, plus the sets logged against it.
///
/// `exerciseID` is the join key and the only identity that matters;
/// `displayName` is a denormalized copy kept so history stays readable if an
/// exercise is later renamed or dropped from the catalog. Never match on the
/// name — that is the bug this field replaced.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `ExerciseID` and `Mass` from Domain.
@Model
final class PlannedExercise {
    /// The catalog key. Resolve it through `ExerciseCatalog` for full details.
    var exerciseID: ExerciseID = ExerciseID(rawValue: "")
    /// Denormalized for display; never used as an identity or a join key.
    var displayName: String = ""
    var order: Int = 0
    var targetSets: Int = 0
    /// Human-readable rep target, e.g. "8-12" or "5".
    var repRange: String = ""
    var suggestedLoad: Mass?
    /// Rest between sets, in seconds — drives the pace timer.
    var restSeconds: Int = 90
    /// Optional rep tempo like "3-0-1-0".
    var tempo: String?
    var notes: String?

    var day: WorkoutDay?

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.exercise)
    var loggedSets: [LoggedSet]? = []

    init(
        exerciseID: ExerciseID = ExerciseID(rawValue: ""), displayName: String = "",
        order: Int = 0, targetSets: Int = 0, repRange: String = "",
        suggestedLoad: Mass? = nil, restSeconds: Int = 90,
        tempo: String? = nil, notes: String? = nil
    ) {
        self.exerciseID = exerciseID
        self.displayName = displayName
        self.order = order
        self.targetSets = targetSets
        self.repRange = repRange
        self.suggestedLoad = suggestedLoad
        self.restSeconds = restSeconds
        self.tempo = tempo
        self.notes = notes
    }

    /// Sets that count toward progression, in logging order.
    var completedWorkingSets: [LoggedSet] {
        (loggedSets ?? []).filter(\.countsForProgression).sorted { $0.setIndex < $1.setIndex }
    }
}
