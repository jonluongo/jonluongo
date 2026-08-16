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
    /// wrote it (`"8-12"`, `"AMRAP"`), or `"—"` when the plan named none.
    /// Never a number the app chose.
    static func targetText(for repRange: String?) -> String {
        let trimmed = (repRange ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }
}

/// How a prescribed effort is written on screen.
///
/// **What it does.** Turns an `IntensityTarget` into the phrase a lifter would
/// read — `"RPE 8"`, `"2 RIR"`, `"80% 1RM"` — for the exercise header, the set
/// rows, and the session preview.
///
/// **How it is used.** Call `label(for:)` and draw the result; `nil` means the
/// plan named no target, and nothing is drawn rather than a placeholder
/// inviting the lifter to invent one.
///
/// **What it depends on.** `IntensityTarget` from LiftingKit. It formats and
/// nothing else: no scale is converted into another, no value is bounded or
/// rounded, and a scale this build has never heard of is shown as written
/// rather than dropped — which is the only honest thing to do with a target
/// somebody deliberately prescribed.
enum IntensityPrescription {

    /// The target as a phrase, or `nil` when there is none.
    static func label(for intensity: IntensityTarget?) -> String? {
        guard let intensity else { return nil }
        let value = intensity.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if intensity.scale == .rpe { return "RPE \(value)" }
        if intensity.scale == .repsInReserve { return "\(value) RIR" }
        if intensity.scale == .percentOfOneRepMax {
            // "80" and "80%" both read as a percentage; neither gains a second
            // per-cent sign, and neither loses one it was written with.
            return value.hasSuffix("%") ? "\(value) 1RM" : "\(value)% 1RM"
        }
        // A scale nobody here has heard of is named and shown, in the words it
        // arrived in. Guessing at a phrasing for it would be inventing one.
        return "\(intensity.scale.rawValue) \(value)"
    }
}
