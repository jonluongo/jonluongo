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
/// `detail(for:in:)` is the logging screen's: it says what one set asks that the
/// exercise's line has not already said, so the sentence describing set four is
/// under set four rather than off the top of the screen by the time he gets
/// there.
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
        guard let repRange = sharedRepRange(of: sets), sharesOneIntensity(sets) else {
            return "\(exercise.targetSets) set\(exercise.targetSets == 1 ? "" : "s")"
        }
        let effort = IntensityPrescription.label(for: sharedIntensity(of: sets))
        return ["\(exercise.targetSets) × \(repRange)", effort]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// What one prescribed set asks that the exercise's own line has not
    /// already said — the effort asked of it, and any note written about it in
    /// particular. `nil` when it adds nothing.
    ///
    /// This is what a set row draws underneath itself, and the reason it draws
    /// nothing most of the time. The load and the reps are left out on purpose:
    /// they are already in front of the lifter as the placeholders in that
    /// row's own two fields, and a line repeating them would be the screen
    /// saying the same thing twice. The effort is left out too when every set
    /// asks for the same one, because the header stated it once for all of
    /// them; it appears only where a set asks for something of its own, which
    /// is what a ramp's top single and a drop set's last set are. A uniform
    /// three-by-eight therefore gains no second line anywhere.
    ///
    /// `set` is `nil` for a warm-up or a set the lifter added past the ones
    /// prescribed, and a set the plan never described asks nothing of him.
    static func detail(for set: SetPrescription?, in exercise: PlannedExercise) -> String? {
        guard let set else { return nil }
        let effort = statesIntensityForEverySet(exercise)
            ? nil
            : IntensityPrescription.label(for: set.intensity)
        let parts = [effort, set.notes.flatMap { $0.isEmpty ? nil : $0 }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    /// Whether `text(for:)` already names an effort covering every set, which
    /// is the one case a row must not repeat it in. It is the summary's own
    /// condition asked as a question, so the two cannot drift apart.
    private static func statesIntensityForEverySet(_ exercise: PlannedExercise) -> Bool {
        let sets = exercise.prescribedSets
        guard sharedRepRange(of: sets) != nil else { return false }
        return IntensityPrescription.label(for: sharedIntensity(of: sets)) != nil
    }

    /// The rep target every set states, or `nil` when they differ or none was
    /// stated — the case in which the summary gives only a count.
    private static func sharedRepRange(of sets: [SetPrescription]) -> String? {
        let reps = Set(sets.map { $0.repRange ?? "" })
        guard reps.count == 1, let repRange = reps.first, !repRange.isEmpty else { return nil }
        return repRange
    }

    /// The one intensity every set states, or `nil` when they differ or none
    /// stated one. Both answers mean the same thing to a caller: there is no
    /// single effort to write above the table.
    private static func sharedIntensity(of sets: [SetPrescription]) -> IntensityTarget? {
        sharesOneIntensity(sets) ? sets.first?.intensity : nil
    }

    /// Whether every set names the same intensity — including all of them
    /// naming none.
    private static func sharesOneIntensity(_ sets: [SetPrescription]) -> Bool {
        Set(sets.map { $0.intensity }).count == 1
    }
}
