import Foundation
import SwiftData
import LiftingKit

/// A prescribed movement within a day, plus the sets logged against it.
///
/// `exerciseID` is the join key and the only identity that matters;
/// `displayName` is a denormalized copy kept so history stays readable if an
/// exercise is later renamed or dropped from the catalog. Never match on the
/// name — that is the bug this field replaced.
///
/// **The sets may differ from one another.** `targetSets` is always how many
/// there are; `statedSets` holds them one at a time when the plan listed them,
/// and is empty when it prescribed the same work throughout. Read
/// `prescribedSets` rather than either — that is the one place a set's own
/// statements and the exercise's are put together, and it is what the workout
/// logger renders and the snapshot reports.
///
/// **It may be performed in a group.** `groupID` says which superset, tri-set
/// or giant set this exercise belongs to and `groupPosition` where in the round
/// it sits; both are `nil` for an exercise performed on its own, which is nearly
/// every exercise. Two optional columns rather than a `SupersetGroup` model,
/// because a relationship and a CloudKit record type would say no more than
/// these do. Read them through `SessionGrouping` rather than directly —
/// reconstructing a day's groups is one job and belongs in one place.
///
/// Every property has a default, as CloudKit requires.
/// Depends on: `ExerciseID`, `Mass`, `IntensityTarget` and `SetPrescription`
/// from LiftingKit, and `PrescribedSet`.
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
    /// Rest taken after a set of this exercise, in seconds — what the pace timer
    /// runs. `nil` when no rest was prescribed, in which case no timer starts
    /// unless the lifter sets one himself.
    ///
    /// **Inside a group this still means what it has always meant**, which is
    /// why a group needs no column of its own for it: nothing is rested after
    /// any member but the last, because the next movement of the round follows
    /// immediately, and the last carries the group's rest after the round. Read
    /// `ExerciseGroup.restSeconds` rather than a member's when you want the
    /// group's.
    var restSeconds: Int?
    /// The group this exercise is performed in — a superset, a tri-set, a giant
    /// set — or `nil` when it is performed on its own. Identity only: what a
    /// group *is* is the exercises sharing this, in `groupPosition` order.
    var groupID: UUID?
    /// Where this exercise sits within its group's round, from zero. `nil`
    /// exactly when `groupID` is.
    var groupPosition: Int?
    /// How hard the work is meant to be, on whatever scale the plan stated.
    /// `nil` when the plan named no target — never inferred from the load.
    var intensity: IntensityTarget?
    /// Optional rep tempo like "3-0-1-0".
    var tempo: String?
    var notes: String?

    var day: WorkoutDay?

    /// The sets the plan listed one at a time. Empty when it prescribed the
    /// same work throughout, which is the ordinary case and stores no rows.
    @Relationship(deleteRule: .cascade, inverse: \PrescribedSet.exercise)
    var statedSets: [PrescribedSet]? = []

    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.exercise)
    var loggedSets: [LoggedSet]? = []

    init(
        exerciseID: ExerciseID = ExerciseID(rawValue: ""), displayName: String = "",
        order: Int = 0, targetSets: Int = 0, repRange: String = "",
        suggestedLoad: Mass? = nil, restSeconds: Int? = nil,
        intensity: IntensityTarget? = nil, tempo: String? = nil, notes: String? = nil
    ) {
        self.exerciseID = exerciseID
        self.displayName = displayName
        self.order = order
        self.targetSets = targetSets
        self.repRange = repRange
        self.suggestedLoad = suggestedLoad
        self.restSeconds = restSeconds
        self.intensity = intensity
        self.tempo = tempo
        self.notes = notes
    }

    /// Whether every set drawn for this exercise has been ticked.
    ///
    /// The question the panel asks to decide whether it is written on the
    /// recorded ground: an exercise finished reads as finished from across the
    /// screen, the way a logged session does on the block. An exercise with no
    /// rows at all is *not* finished — there is nothing to have done — which is
    /// why the emptiness is checked rather than `allSatisfy` answering `true`
    /// for it.
    var isFullyLogged: Bool {
        let sets = loggedSets ?? []
        return !sets.isEmpty && sets.allSatisfy(\.isCompleted)
    }

    /// Sets that count toward progression, in logging order.
    var completedWorkingSets: [LoggedSet] {
        (loggedSets ?? []).filter(\.countsForProgression).sorted { $0.setIndex < $1.setIndex }
    }

    /// The sets the plan listed, in the order it listed them.
    var orderedStatedSets: [PrescribedSet] {
        (statedSets ?? []).sorted { $0.order < $1.order }
    }

    /// Every set this exercise prescribes, in order, each stated in full.
    ///
    /// The one thing to read when rendering the prescription or reporting it
    /// back. A uniform prescription reads as `targetSets` copies of what the
    /// exercise states; a listed one reads as what each set states with
    /// anything it left out taken from the exercise. The rule lives in
    /// `SetPrescription.everySet(...)`, shared with the document side so the
    /// phone and the server cannot disagree about what a plan prescribed.
    var prescribedSets: [SetPrescription] {
        SetPrescription.everySet(
            stated: orderedStatedSets.map(\.prescription), count: targetSets,
            repRange: repRange, suggestedLoad: suggestedLoad, intensity: intensity
        )
    }
}
