import Foundation

/// One set as the lifter logged it: what he lifted, for how many, for how long
/// or how far, and when.
///
/// **Nothing here says how hard it felt.** The lifter is asked for no rating,
/// so none is reported: what the plan asked for is in `prescribedSets` and what
/// he did is here, and 4 × 8-10 prescribed against 10/10/9/8 logged says what a
/// self-reported number was supposed to. A permanently-null rating field would
/// read as a lifter who declined to answer a question nobody put to him.
///
/// A row exists as soon as it is on screen, so read `isCompleted` rather than
/// existence to know work was done, and `isWarmup` to know whether it counts.
/// `load` is `nil` for a bodyweight movement rather than zero, so "no external
/// weight" and "an empty bar" stay distinguishable.
///
/// **A set is counted, held, or carried, and no two of those are the same
/// number.** A plank held for 34 seconds reads `reps: 0`,
/// `durationSeconds: 34`, `distance: null`; a farmer's carry over 40 metres
/// reads `reps: 0`, `durationSeconds: null`, `distance: {"value": 40, "unit":
/// "m"}`; a set of five reads `reps: 5` and null for both. Add seconds or metres
/// into a rep total and every volume report that follows is wrong, which is
/// exactly what these separate fields exist to stop. Each is `nil` — never zero
/// — when the set did not record it, because a set that was not timed did not
/// last no time and one that was not carried did not travel no distance.
///
/// Depends on: `Mass`, `Distance`.
public struct SnapshotLoggedSet: Codable, Hashable, Sendable {
    /// Position within the exercise, ascending.
    public let setIndex: Int
    /// The weight as entered, in the unit entered. `nil` means bodyweight.
    public let load: Mass?
    /// Repetitions performed. `0` for a set logged as a hold or a carry.
    public let reps: Int
    /// How long the set was held, in whole seconds. `nil` when the set was
    /// counted or carried rather than timed — never zero.
    public let durationSeconds: Int?
    /// How far the set was carried, in the unit it was prescribed in. `nil` when
    /// the set was counted or held rather than carried — never zero. The unit
    /// travels with the number and is never converted: forty yards is not forty
    /// metres, and no reader here may decide it is.
    public let distance: Distance?
    public let isCompleted: Bool
    public let isWarmup: Bool
    public let completedAt: Date

    public init(
        setIndex: Int, load: Mass?, reps: Int, durationSeconds: Int? = nil,
        distance: Distance? = nil,
        isCompleted: Bool, isWarmup: Bool, completedAt: Date
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
}
