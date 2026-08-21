import Foundation
import SwiftData
import LiftingKit

/// One set the lifter actually did.
///
/// **A row exists only if it happened.** Nothing seeds these, so there is no
/// `isCompleted` to distinguish a row that means something from one that does
/// not. That boolean existed because a row was created for every prescribed set
/// the moment a screen opened, which also gave `reps` a default of zero — and a
/// completed working set at `185 lb × 0` is what the coach then read.
///
/// **Every measure is optional, and they never mix.** `nil` is *he did not say*;
/// a number is *he did that much*. A hold is seconds, a carry is a distance in
/// the unit it was prescribed in, and neither is ever added into a rep total —
/// that would be a number nobody performed, propagating into every report that
/// follows.
///
/// **Rest taken is not stored.** It is the gap between consecutive `completedAt`
/// timestamps, which is truer than what a timer counted: a timer that ran three
/// minutes says nothing about the minute spent talking afterwards.
///
/// **What it depends on.** `Mass` and `Distance` from LiftingKit.
///
/// Every property has a default, as CloudKit requires.
@Model
final class PerformedSet {

    /// Where this sat among the exercise's sets, from 0.
    var setIndex: Int = 0
    /// Whether this was performed as a warm-up.
    ///
    /// Stated here as well as on the prescription, and the two may honestly
    /// disagree: a lifter treats a prescribed working set as a warm-up often
    /// enough, and a set he added has no prescription to inherit from.
    var isWarmup: Bool = false
    /// What was on the bar. `nil` for bodyweight, and `nil` when he did not say.
    var load: Mass?
    /// How many. `nil` when he ticked the set without stating a count — which is
    /// not the same as doing none, and is why this is optional rather than zero.
    var reps: Int?
    /// How long it was held. `nil` when it was not timed.
    var durationSeconds: Int?
    /// How far it was carried, in the unit it was prescribed in. Never
    /// converted: forty metres and forty yards are different work.
    var distance: Distance?
    /// The moment the set was recorded. Consecutive values are what rest taken
    /// is derived from.
    var completedAt: Date = Date()

    var exercise: PerformedExercise?
    /// The set this fulfils, or `nil` for one the lifter added and for a stated
    /// baseline.
    var planned: PlannedSet?

    init(
        setIndex: Int = 0, isWarmup: Bool = false, load: Mass? = nil,
        reps: Int? = nil, durationSeconds: Int? = nil, distance: Distance? = nil,
        completedAt: Date = Date()
    ) {
        self.setIndex = setIndex
        self.isWarmup = isWarmup
        self.load = load
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distance = distance
        self.completedAt = completedAt
    }

    /// Whether this set counts toward progression: work rather than a warm-up.
    /// There is no completion to check — the row exists because it happened.
    var countsForProgression: Bool { !isWarmup }
}
