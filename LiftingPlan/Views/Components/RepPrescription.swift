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

/// What a prescribed hold puts into a set the app creates, and which of the two
/// things a set can record it records.
///
/// **What it does.** Answers, for one prescription, whether the work is held
/// for time rather than counted (`isTimed`), and what a new row is seeded with
/// when it is (`seededSeconds`). It is `RepPrescription`'s mirror, and between
/// them a prescribed target reaches the lifter as the unit it was written in.
///
/// **How it is used.** `ExerciseLogSection` asks `isTimed(_: PlannedExercise)`
/// to label the column and to bind each row to the set's seconds instead of its
/// reps; `ActiveWorkoutView` asks `seededSeconds` when it lays a session out.
/// A hold whose text names one duration is seeded with it, exactly as a rep
/// target naming one number is; a range seeds nothing, because choosing an end
/// of it would be the app deciding how long to hold.
///
/// **What it depends on.** `WorkDuration` from LiftingKit, which does the
/// reading, and `PlannedExercise` for the whole-exercise question. It decides
/// nothing about training: an exercise is timed because its prescription says
/// so, never because of anything the lifter did.
enum HoldPrescription {

    /// Whether this target is work held for time rather than counted.
    static func isTimed(_ target: String?) -> Bool {
        WorkDuration(target ?? "").isTimed
    }

    /// Whether this exercise's work is held for time.
    ///
    /// One answer for the whole exercise, because the column above the set
    /// table is one word and it must not lie about the rows under it. An
    /// exercise counts as timed when anything it prescribes is — its own target
    /// or any of its sets' — which is what a plank prescribed as three
    /// thirty-second holds looks like from either direction.
    static func isTimed(_ exercise: PlannedExercise) -> Bool {
        isTimed(exercise.repRange)
            || exercise.prescribedSets.contains { isTimed($0.repRange) }
    }

    /// The hold to seed into a new set, in seconds, or `nil` when the
    /// prescription names no single duration — a range, or no target at all.
    static func seededSeconds(for target: String?) -> Int? {
        WorkDuration(target ?? "").seconds
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
