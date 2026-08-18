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
/// **How it is used.** Three callers, and which one they use turns on whether
/// there is a table under the line. `PrescribedExerciseRow` browses a session
/// with no table beneath it and calls `text(for:unit:)` for the whole
/// prescription. The logging screen's headers have the table, so they call
/// `aboveTable(for:)`, which states only what no row of it will. `detail(for:in:)`
/// is the row's own: what *this* set asks that the header has not said, so the
/// sentence describing set four is under set four rather than off the top of the
/// screen by the time he gets there.
///
/// **Every exercise gets one line, and a varying prescription is spanned rather
/// than enumerated.** A ramp used to draw its count and then a numbered line per
/// set, so one exercise in a list read as a different kind of object from its
/// neighbours and the count above the lines restated what the lines already
/// said. The span is what a browsing screen can honestly say — the *whole* of
/// what is prescribed still reaches the lifter set by set on the logging screen,
/// where the work happens, and that is the entire argument for summarising here.
///
/// **What it depends on.** `PlannedExercise`, `SetPrescription`,
/// `IntensityPrescription` and `TargetSpan`. It states what the plan said and
/// never rounds, averages, or picks one set to stand for the rest: a figure is
/// written only when every set states it, and otherwise only as the span the
/// sets actually cover.
enum PrescriptionSummary {

    /// The one-line summary of a whole prescription: how many sets, what they
    /// ask for, and one more thing about them.
    ///
    /// **One thing, because the line holds one.** It shares a row with the rest
    /// the exercise prescribes, and about eighteen characters is all that leaves
    /// it; a line that tried to say the reps, the load and the effort at once
    /// lost its tail to an ellipsis, and `4 × 8/AMRAP · 30-6…` says less than a
    /// shorter line that chose. So it spends the room on whatever makes these
    /// sets differ from one another — the span of load a ramp climbs — and on
    /// the effort when they do not differ at all. What is left out is not lost:
    /// the logging screen states every set of it in full, on the row it is
    /// lifted on.
    ///
    /// `unit` is the lifter's display unit, so a load written in pounds is read
    /// in the unit he reads everything else in. The conversion is a display one;
    /// nothing rewrites what was prescribed.
    static func text(for exercise: PlannedExercise, unit: MassUnit) -> String {
        let sets = exercise.prescribedSets
        let count = exercise.targetSets
        let work = target(of: sets).map { "\(count) × \($0)" }
            ?? "\(count) set\(count == 1 ? "" : "s")"
        return [work, difference(in: sets, unit: unit)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The one thing said beside the count and the target.
    ///
    /// The span of load first, because where the sets ask for the same work and
    /// differ in what is on the bar, that span is the only thing on the line
    /// saying they differ at all — and it is asked only when the target is
    /// shared, since a target that already reads `8/AMRAP` has said it. Then the
    /// effort: the one every set asks for, or the span of the ones they ask for
    /// between them.
    private static func difference(in sets: [SetPrescription], unit: MassUnit) -> String? {
        if sharesOneTarget(sets), let load = varyingLoad(of: sets, unit: unit) { return load }
        return effort(of: sets)
    }

    /// What the header above a set table must state, because no row of that
    /// table will state it.
    ///
    /// **The table already says the count and the target.** `3 × 10-12` above
    /// three rows whose rep fields each read `10-12` is the screen saying the
    /// same thing twice, and the second saying is the one competing with the
    /// sets for the top of the card. The same goes for a ramp's span of load:
    /// every row carries its own load as its own placeholder. A browsing screen
    /// has no table under it and still needs the whole line — that is what
    /// `text(for:unit:)` is, and `PrescribedExerciseRow` still calls it.
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

    /// What the sets ask for between them — reps, a hold, or a carry, in the
    /// words they were written in. `nil` when any set states no target, since a
    /// figure covering a set nobody prescribed one for would be an invention.
    private static func target(of sets: [SetPrescription]) -> String? {
        TargetSpan.text(covering: sets.map { $0.repRange ?? "" })
    }

    /// Whether every set asks for the same target — including all of them
    /// asking for none, which differ in nothing either.
    private static func sharesOneTarget(_ sets: [SetPrescription]) -> Bool {
        Set(sets.map { $0.repRange ?? "" }).count == 1
    }

    /// The span of load across the sets, written only when they differ — that
    /// difference is the whole of what a ramp or a drop set *is*, and it is what
    /// the numbered block used five rows to say. `nil` when the loads are all
    /// alike, and when any set was given none.
    private static func varyingLoad(of sets: [SetPrescription], unit: MassUnit) -> String? {
        let loads = sets.compactMap { $0.suggestedLoad?.converted(to: unit).value }
        guard loads.count == sets.count, let low = loads.min(), let high = loads.max(),
            low != high
        else { return nil }
        return "\(low.compactString)-\(high.compactString) \(unit.rawValue)"
    }

    /// The effort asked of the sets: the one target when they all state it, and
    /// the span of the values when they state different ones on the same scale.
    /// `nil` when any set states none, and when two of them are written on
    /// scales that cannot be spanned — RPE and a percentage of a maximum are two
    /// different sentences, and no range covers both.
    private static func effort(of sets: [SetPrescription]) -> String? {
        let intensities = sets.compactMap(\.intensity)
        let scales = Set(intensities.map(\.scale))
        guard intensities.count == sets.count, scales.count == 1, let scale = scales.first,
            let span = TargetSpan.text(covering: intensities.map(\.value))
        else { return nil }
        return IntensityPrescription.label(for: IntensityTarget(scale: scale, value: span))
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
