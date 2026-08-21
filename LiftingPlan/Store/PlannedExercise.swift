import Foundation
import SwiftData
import LiftingKit

/// One movement the coach prescribed in a session, and how to perform it.
///
/// **What it does.** Names the movement, where it sits in the session, how long
/// to rest after it, what the coach wants said about it, and which superset it
/// belongs to if any. Its sets hang off it, each stated in full.
///
/// **Nothing here is a default for its sets to override.** There is no rep
/// range, no load and no set count on this type: a set states itself. That
/// reconciliation — an exercise's prescription completed by each set's own — was
/// where a prescription could quietly become something the coach did not write,
/// and it also meant two code paths for what is one idea.
///
/// **A superset is `groupOrdinal` plus `order`.** Members of one group share the
/// ordinal and sit next to each other; round *N* is the *N*th working set of each
/// member, taken in `order`. Rest falls out per exercise — nothing after the
/// first member, the round's rest after the last — so no separate group row is
/// needed to hold it.
///
/// **What it depends on.** `ExerciseID` from LiftingKit. It resolves nothing:
/// what a movement is called and what it trains come from the catalog, keyed by
/// this ID.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PlannedExercise {

    /// The catalog's identity for this movement. History is keyed by it, so a
    /// fabricated one fragments a lift's history irreparably — which is why an
    /// ID the catalog does not have is refused before it reaches here.
    var exerciseID: ExerciseID = ExerciseID(rawValue: "")
    /// Where this sits in the session, from 0. Group members are contiguous.
    var order: Int = 0
    /// How long to rest after this movement. `nil` when the coach did not say.
    var restSeconds: Int?
    /// What the coach wants said about the movement — a cue, a tempo, what to
    /// watch. `nil` when there is none.
    var coachNote: String?
    /// Which superset this belongs to within its session, or `nil` when it is
    /// performed on its own. A small integer rather than a UUID: it means
    /// nothing outside one session.
    var groupOrdinal: Int?

    var session: Session?

    @Relationship(deleteRule: .cascade, inverse: \PlannedSet.exercise)
    var sets: [PlannedSet]? = []

    @Relationship(deleteRule: .nullify, inverse: \PerformedExercise.planned)
    var performed: [PerformedExercise]? = []

    init(
        exerciseID: ExerciseID = ExerciseID(rawValue: ""), order: Int = 0,
        restSeconds: Int? = nil, coachNote: String? = nil, groupOrdinal: Int? = nil
    ) {
        self.exerciseID = exerciseID
        self.order = order
        self.restSeconds = restSeconds
        self.coachNote = coachNote
        self.groupOrdinal = groupOrdinal
    }

    /// Prescribed sets in the order they are to be performed.
    var orderedSets: [PlannedSet] {
        (sets ?? []).sorted { $0.setIndex < $1.setIndex }
    }

    /// The working sets, in order — what a round of a superset counts and what
    /// progression is read from. A warm-up belongs to its exercise and precedes
    /// the group.
    var workingSets: [PlannedSet] { orderedSets.filter { !$0.isWarmup } }
}
