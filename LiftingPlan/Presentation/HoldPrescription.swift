import Foundation
import LiftingKit

/// What a prescribed hold puts into a set the app creates, and which of the two
/// things a set can record it records.
///
/// **What it does.** Answers, for one prescription, whether the work is held
/// for time rather than counted (`isTimed`), and what a new row is seeded with
/// when it is (`seededSeconds`). It is `RepPrescription`'s mirror, and between
/// them a prescribed target reaches the lifter as the unit it was written in.
///
/// **How it is used.** `ActiveWorkoutView` asks `seededSeconds` when it lays a
/// session out. A hold whose text names one duration is seeded with it, exactly
/// as a rep target naming one number is; a range seeds nothing, because choosing
/// an end of it would be the app deciding how long to hold. Which of the three
/// things a row records is asked of `WorkPrescription`, not here.
///
/// **What it depends on.** `WorkDuration` from LiftingKit, which does the
/// reading. It decides nothing about training: an exercise is timed because its
/// prescription says so, never because of anything the lifter did.
enum HoldPrescription {

    /// Whether this target is work held for time rather than counted.
    static func isTimed(_ target: String?) -> Bool {
        WorkDuration(target ?? "").isTimed
    }

    /// The hold to seed into a new set, in seconds, or `nil` when the
    /// prescription names no single duration — a range, or no target at all.
    static func seededSeconds(for target: String?) -> Int? {
        WorkDuration(target ?? "").seconds
    }
}
