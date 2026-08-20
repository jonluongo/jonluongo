import Foundation
import LiftingKit

/// How a prescription is written on screen, for the exercise as a whole and for
/// one of its sets.
///
/// **What it does.** Builds the one line the lifter reads above a set table and
/// beside an exercise's name in a session he is browsing: `"3 × 8-12 · RPE 8"`
/// for an exercise whose sets are all the same, `"3 × 5 · 60-80 kg"` for a ramp,
/// `"4 × 8 / AMRAP · 70-100 kg"` for a drop set.
///
/// **How it is used.** Two callers, both on the logging screen, and both saying
/// only what the table under them will not. An exercise's header calls
/// `aboveTable(for:)` — the effort every set shares, which no row states because
/// each row would state it identically. A set row calls `detail(for:in:)` for
/// what *this* set asks that the header has not said, so the sentence describing
/// set four is under set four rather than off the top of the screen by the time
/// he gets there.
///
/// It had a third, `text(for:unit:)`, which wrote the whole prescription on one
/// line — `3 × 5 · 60-80 kg` — for a screen browsing a session it had no table
/// for. Both such screens were deleted, and it went with them, along with the
/// span arithmetic that existed to write it.
///
/// **What it depends on.** `PlannedExercise`, `SetPrescription`,
/// `IntensityPrescription`. It states what the plan said and
/// never rounds, averages, or picks one set to stand for the rest: a figure is
/// written only when every set states it, and otherwise only as the span the
/// sets actually cover.
enum PrescriptionSummary {

    /// What the header above a set table must state, because no row of that
    /// table will state it.
    ///
    /// **The table already says the count and the target.** `3 × 10-12` above
    /// three rows whose rep fields each read `10-12` is the screen saying the
    /// same thing twice, and the second saying is the one competing with the
    /// sets for the top of the card. The same goes for a ramp's span of load:
    /// every row carries its own load as its own placeholder. A browsing screen
    /// has no table under it and still needs the whole line — which is what the
    /// third function wrote, and both such screens went before it did.
    ///
    /// **What a row cannot say is the effort every set shares.** `unloadedEffort`
    /// deliberately draws nothing when all the sets ask for the same one, on the
    /// grounds that this line stated it once for all of them — so removing this
    /// line without replacing it would take the intensity off the logging screen
    /// altogether. Where the sets ask for different efforts each row states its
    /// own, and then there is nothing left here to add.
    ///
    /// `nil` when the table says everything, which is the ordinary case.
    static func aboveTable(for exercise: PlannedExercise) -> String? {
        guard statesIntensityForEverySet(exercise) else { return nil }
        return IntensityPrescription.label(for: exercise.prescribedSets.first?.intensity)
    }

    /// What one prescribed set asks that the exercise's own line has not
    /// already said — the effort asked of it, and any note written about it in
    /// particular. `nil` when it adds nothing.
    ///
    /// This is what a set row draws underneath itself, and the reason it draws
    /// nothing most of the time. The load and the reps are left out on purpose:
    /// they are already in front of the lifter as the placeholders in that
    /// row's own two fields, and a line repeating them would be the screen
    /// saying the same thing twice.
    ///
    /// `set` is `nil` for a warm-up or a set the lifter added past the ones
    /// prescribed, and a set the plan never described asks nothing of him.
    static func detail(for set: SetPrescription?, in exercise: PlannedExercise) -> String? {
        guard let set else { return nil }
        let parts = [
            unloadedEffort(of: set, in: exercise),
            set.notes.flatMap { $0.isEmpty ? nil : $0 },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The effort asked of this set, written only where nothing else on the row
    /// has already said how hard to work.
    ///
    /// **A set with a load prescribed is not shown its intensity.** The
    /// intensity is already baked into the number on the bar — a coach who
    /// writes 100 kg for five has done the reasoning an RPE is the shorthand
    /// for, and printing both under every row is showing his working. Where no
    /// load was prescribed the intensity *is* the prescription: "work up to a
    /// top single at RPE 8" leaves the lifter nothing else to go on, and hiding
    /// it would leave the row blank. The same conditional shape as the rest
    /// line, which appears only where a rest was prescribed.
    ///
    /// It is left out too when every set asks for the same effort, because the
    /// exercise's own line above the table stated it once for all of them; it
    /// appears wherever a set asks for something of its own, which is what a
    /// ramp's top single and a drop set's last set are — and it appears even
    /// when that line states a span, because a span says what the sets cover
    /// between them and not what *this* set is being asked for.
    private static func unloadedEffort(
        of set: SetPrescription, in exercise: PlannedExercise
    ) -> String? {
        guard set.suggestedLoad == nil, !statesIntensityForEverySet(exercise) else { return nil }
        return IntensityPrescription.label(for: set.intensity)
    }

    /// Whether every set asks for the same effort, which is the one case a row
    /// has nothing of its own to say about it — the exercise's own line above
    /// the table has already stated that one figure for all of them. A line
    /// stating a span has not said what any one set asks for, so it does not
    /// silence the rows.
    private static func statesIntensityForEverySet(_ exercise: PlannedExercise) -> Bool {
        let sets = exercise.prescribedSets
        guard sharesOneIntensity(sets) else { return false }
        return IntensityPrescription.label(for: sets.first?.intensity) != nil
    }

    /// Whether every set names the same intensity — including all of them
    /// naming none.
    private static func sharesOneIntensity(_ sets: [SetPrescription]) -> Bool {
        Set(sets.map { $0.intensity }).count == 1
    }
}
