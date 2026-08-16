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
/// **A set is counted or it is held, and the two are different numbers.** A
/// plank held for 34 seconds records `durationSeconds` 34 and `reps` 0; a set
/// of five records the reverse. They are separate fields rather than one
/// number with a unit beside it because everything downstream — the snapshot,
/// `volume_by_muscle`, the history a progression is read out of — totals reps,
/// and a hold that arrived in that column was thirty-four repetitions nobody
/// performed. Which one a row records is decided by what the plan prescribed
/// for it, in `WorkDuration`, and never by what the lifter happened to type.
///
/// Every property has a default or is optional, as CloudKit requires.
/// Depends on: `Mass` from Domain.
@Model
final class LoggedSet {
    var setIndex: Int = 0
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    var load: Mass?
    /// Repetitions performed. `0` on a row that records a hold.
    var reps: Int = 0
    /// How long the set was held, in whole seconds. `nil` — never zero — when
    /// the row counts repetitions instead: a set that was not timed did not
    /// last no time.
    var durationSeconds: Int?
    /// Rating of perceived exertion, 1–10.
    var rpe: Double?
    var isCompleted: Bool = false
    /// Warmup sets show as "W" and are excluded from progression math.
    var isWarmup: Bool = false
    var completedAt: Date = Date()

    var exercise: PlannedExercise?

    init(
        setIndex: Int = 0, load: Mass? = nil, reps: Int = 0, durationSeconds: Int? = nil,
        rpe: Double? = nil, isCompleted: Bool = false, isWarmup: Bool = false,
        completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.load = load
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.rpe = rpe
        self.isCompleted = isCompleted
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }

    /// A completed working set — the kind progression counts.
    var countsForProgression: Bool { isCompleted && !isWarmup }
}
