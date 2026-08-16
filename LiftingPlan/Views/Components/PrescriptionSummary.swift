import Foundation
import LiftingKit

/// How a prescription is written on screen, for the exercise as a whole and for
/// one of its sets.
///
/// **What it does.** Builds the lines the lifter reads above a set table and in
/// a session preview: `"3 × 8-12 · RPE 8"` for an exercise whose sets are all
/// the same, `"4 sets"` for one whose sets differ, and `"80 kg × 5 · RPE 9"`
/// for a single set of a ramp.
///
/// **How it is used.** `ExerciseLogSection`, `ActiveWorkoutView`'s header and
/// `SessionDetailView` call it rather than each assembling a line of their own,
/// so the same prescription reads the same way everywhere in the app.
///
/// **What it depends on.** `PlannedExercise`, `SetPrescription` and
/// `IntensityPrescription`. It states what the plan said and never summarizes
/// away a difference: an exercise whose sets differ is not given one rep range
/// that no set of it actually has, because the lifter would then be reading a
/// prescription nobody wrote. The sets say the rest, one row at a time.
enum PrescriptionSummary {

    /// The one-line summary of a whole prescription.
    ///
    /// A uniform prescription states its count, its reps and its effort. One
    /// whose sets differ states only how many there are — the per-set lines
    /// carry what each of them actually asks for.
    static func text(for exercise: PlannedExercise) -> String {
        let sets = exercise.prescribedSets
        let reps = Set(sets.map { $0.repRange ?? "" })
        let intensities = Set(sets.map { $0.intensity })

        guard reps.count == 1, intensities.count == 1,
            let repRange = reps.first, !repRange.isEmpty
        else {
            return "\(exercise.targetSets) set\(exercise.targetSets == 1 ? "" : "s")"
        }
        let effort = IntensityPrescription.label(for: intensities.first ?? nil)
        return ["\(exercise.targetSets) × \(repRange)", effort]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// One prescribed set as a line: its load, its reps, its effort, its note —
    /// each part dropped when the plan did not state it. Empty when the plan
    /// stated nothing at all about the set, which is a set with nothing to say.
    ///
    /// `unit` is the lifter's display unit, so a load written in pounds is read
    /// in the unit he reads everything else in. The conversion is a display
    /// one; nothing rewrites what was prescribed.
    static func text(for set: SetPrescription, unit: MassUnit) -> String {
        let load = set.suggestedLoad.map {
            "\($0.converted(to: unit).value.compactString) \(unit.rawValue)"
        }
        let reps = set.repRange.flatMap { $0.isEmpty ? nil : $0 }
        let work = [load, reps].compactMap { $0 }.joined(separator: " × ")

        return [work.isEmpty ? nil : work,
                IntensityPrescription.label(for: set.intensity),
                set.notes.flatMap { $0.isEmpty ? nil : $0 }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Whether this exercise's sets differ from one another, which is what
    /// decides whether the lifter is shown a per-set breakdown at all.
    static func setsDiffer(in exercise: PlannedExercise) -> Bool {
        !exercise.orderedStatedSets.isEmpty
            && Set(exercise.prescribedSets).count > 1
    }
}
