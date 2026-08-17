import Foundation
import SwiftData
import LiftingKit

/// One set of one exercise, as the lifter logged it.
///
/// A row exists as soon as it is on screen, so `isCompleted` — not existence —
/// marks work as done, and checking it is what starts the rest timer. `load`
/// is `nil` for bodyweight movements rather than zero, so "no external weight"
/// and "an empty bar" stay distinguishable.
///
/// **A set is counted, held, or carried, and no two of those are the same
/// number.** A plank held for 34 seconds records `durationSeconds` 34 and `reps`
/// 0; a farmer's carry over 38 metres records `distance` and nothing else; a set
/// of five records only its reps. They are separate fields rather than one
/// number with a unit beside it because everything downstream — the snapshot,
/// `volume_by_muscle`, the history a progression is read out of — totals reps,
/// and a hold that arrived in that column was thirty-four repetitions nobody
/// performed. Which one a row records is decided by what the plan prescribed
/// for it, in `WorkMeasure`, and never by what the lifter happened to type.
///
/// **It records what he did, and asks him nothing about it.** There is no
/// self-reported rating here. The owner could not honestly tell one rep in
/// reserve from three, and a number nobody can supply accurately is worse than
/// none — a reader would trust it and program against it. What the plan asked
/// for sits beside these sets in the snapshot, so the reps and the load
/// answer the question a rating was standing in for.
///
/// Every property has a default or is optional, as CloudKit requires. A store
/// written before a field existed keeps every row it had and reads the new field
/// as absent; a store written with a field this build no longer has keeps every
/// row too, and the retired column is simply left behind unread. Both were
/// verified by reconstructing such a store on disk and reopening it under this
/// schema rather than by reading the code.
/// Depends on: `Mass` and `Distance` from Domain.
@Model
final class LoggedSet {
    var setIndex: Int = 0
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    var load: Mass?
    /// Repetitions performed. `0` on a row that records a hold or a carry.
    var reps: Int = 0
    /// How long the set was held, in whole seconds. `nil` — never zero — when
    /// the row counts repetitions or carries a distance instead: a set that was
    /// not timed did not last no time.
    var durationSeconds: Int?
    /// How far the set was carried, in the unit the plan prescribed it in.
    /// `nil` — never zero — when the row counts repetitions or records a hold
    /// instead: a set that was not carried did not travel no distance. The unit
    /// is stored beside the number and never converted, exactly as `load` is.
    var distance: Distance?
    var isCompleted: Bool = false
    /// Warmup sets show as "W" and are excluded from progression math.
    var isWarmup: Bool = false
    var completedAt: Date = Date()

    var exercise: PlannedExercise?

    init(
        setIndex: Int = 0, load: Mass? = nil, reps: Int = 0, durationSeconds: Int? = nil,
        distance: Distance? = nil, isCompleted: Bool = false,
        isWarmup: Bool = false, completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.load = load
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distance = distance
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }

    /// A completed working set — the kind progression counts.
    var countsForProgression: Bool { isCompleted && !isWarmup }
}
