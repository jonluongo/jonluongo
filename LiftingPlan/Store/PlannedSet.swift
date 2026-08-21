import Foundation
import SwiftData
import LiftingKit

/// One set the coach prescribed: what to do, with what, and how hard.
///
/// **Every prescribed set is a row.** A ramp, a drop set and three identical
/// sets are one shape. Nothing is inherited from the exercise, because there is
/// nothing on the exercise to inherit — which is what removed the second code
/// path and the place a prescription could drift from what was written.
///
/// **`nil` means he did not say.** An absent load is the lifter picking the bar,
/// which is what `intensity` is for; an absent target is a set defined entirely
/// by its load. Nothing here is ever filled in with a number the app chose.
///
/// **What it depends on.** `Target`, `Mass` and `IntensityTarget` from
/// LiftingKit. It judges nothing: a load is never turned into an intensity, an
/// intensity never into a load.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PlannedSet {

    /// Where this sits among the exercise's sets, from 0. Warm-ups are included
    /// in the sequence; a round of a superset counts working sets only.
    var setIndex: Int = 0
    /// Whether the coach prescribed this as a warm-up.
    ///
    /// He could not say this before: everything prescribed was hardcoded as
    /// work, and only a set the lifter added himself was ever marked, so
    /// *"ramp three sets to your top set"* had no way of being written down.
    var isWarmup: Bool = false
    /// The external load. `nil` for a bodyweight movement, and `nil` when the
    /// coach left the bar to the lifter.
    var load: Mass?
    /// How hard this set should be. `nil` when the coach stated none — never a
    /// zero, and never inferred from the load.
    var intensity: IntensityTarget?
    /// What this set asks for — a count, a hold, or a carry. Read once at the
    /// document boundary and stored as the thing it is, so nothing downstream
    /// scans text to find out what a number means.
    var target: Target?

    var exercise: PlannedExercise?

    @Relationship(deleteRule: .nullify, inverse: \PerformedSet.planned)
    var performed: [PerformedSet]? = []

    init(
        setIndex: Int = 0, isWarmup: Bool = false, load: Mass? = nil,
        intensity: IntensityTarget? = nil, target: Target? = nil
    ) {
        self.setIndex = setIndex
        self.isWarmup = isWarmup
        self.load = load
        self.intensity = intensity
        self.target = target
    }

    /// Which of the three things this set is measured in, or `nil` when the
    /// coach stated no target at all.
    var measure: WorkMeasure? { target?.measure }
}
