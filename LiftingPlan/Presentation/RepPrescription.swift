import Foundation
import LiftingKit

/// What a prescribed rep target puts into a set the app creates, and what it
/// shows when it puts nothing.
///
/// Used by `ActiveWorkoutView` when it seeds a session's sets and, through
/// `WorkPrescription.targetFigure`, when a row labels an empty work field. The rule is the one the
/// whole app runs on: the prescription reaches the lifter unaltered, and
/// nothing else does. A target that names one number (`"5"`) is seeded as that
/// number. A target that names a range (`"8-12"`) names no single number, so
/// nothing is seeded and the range is shown as the target instead — picking an
/// end of a range would be the app deciding how hard to train, and picking
/// what the lifter happened to do last time would be it quietly dropping the
/// prescription altogether. Last session's performance belongs beside the
/// field as reference, never inside it.
///
/// A `nil` target is a set that stated no reps, which is the same as an empty
/// one and is answered the same way: nothing seeded, nothing shown.
///
/// Depends on: `RepRange` from LiftingKit.
enum RepPrescription {

    /// The rep count to seed into a new set, or `nil` when the prescription
    /// names no single number — a range, or no target at all.
    static func seededReps(for repRange: String?) -> Int? {
        let range = RepRange(repRange ?? "")
        guard !range.isEmpty, range.lowerBound == range.upperBound else { return nil }
        return range.lowerBound
    }

    /// What an empty rep field shows: the prescribed target exactly as the plan
    /// wrote it (`"8-12"`, `"AMRAP"`), and nothing at all when the plan named
    /// none. Never a number the app chose.
    ///
    /// It used to show `—` for an absent target, which put a mark inside a field
    /// whose job is to invite a number. A placeholder is a hint about what to
    /// type; a dash hints at nothing, and a fresh session drew two of them on
    /// every row, so a table waiting to be filled in read as a table that was
    /// broken. The column header says what the field holds. An empty field
    /// says the plan asked for no figure, which is the truth.
    static func targetText(for repRange: String?) -> String {
        (repRange ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
