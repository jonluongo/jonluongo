import Foundation
import LiftingKit

/// What a prescribed rep target puts into a set the app creates, and what it
/// shows when it puts nothing.
///
/// Used by `ActiveWorkoutView` when it seeds a session's sets and by
/// `SetRowView` when it labels an empty rep field. The rule is the one the
/// whole app runs on: the prescription reaches the lifter unaltered, and
/// nothing else does. A target that names one number (`"5"`) is seeded as that
/// number. A target that names a range (`"8-12"`) names no single number, so
/// nothing is seeded and the range is shown as the target instead — picking an
/// end of a range would be the app deciding how hard to train, and picking
/// what the lifter happened to do last time would be it quietly dropping the
/// prescription altogether. Last session's performance belongs beside the
/// field as reference, never inside it.
///
/// Depends on: `RepRange` from LiftingKit.
enum RepPrescription {

    /// The rep count to seed into a new set, or `nil` when the prescription
    /// names no single number — a range, or no target at all.
    static func seededReps(for repRange: String) -> Int? {
        let range = RepRange(repRange)
        guard !range.isEmpty, range.lowerBound == range.upperBound else { return nil }
        return range.lowerBound
    }

    /// What an empty rep field shows: the prescribed target exactly as the plan
    /// wrote it (`"8-12"`, `"AMRAP"`), or `"—"` when the plan named none.
    /// Never a number the app chose.
    static func targetText(for repRange: String) -> String {
        let trimmed = repRange.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }
}
