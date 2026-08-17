import SwiftUI
import LiftingKit

/// One prescribed exercise, read before it is trained: its name, what the plan
/// asks of it, and whether it has already been logged.
///
/// **What it does.** States the plan and nothing else. The sets it asks for and
/// the effort it asks for sit beside a repeat glyph, and the rest it prescribes
/// beside a clock — and the rest is absent when the plan prescribed none, since
/// a session that asks for no rest shows none rather than `0s`. When the sets
/// differ from one another they are listed one at a time, because no single line
/// can state a ramp or a drop set without naming a figure no set of it actually
/// has.
///
/// **Tempo is not here.** It is a per-rep instruction, and the place it is
/// needed is under the bar: `ExerciseHeaderView` states it on the logging
/// screen. A third column of it here cost a line on every exercise to answer a
/// question nobody asks while deciding whether to go to the gym.
///
/// **How it is used.** The Today screen draws one per exercise of the day it is
/// showing. It was the session preview screen's row; that screen showed the same
/// session Today now shows, one tap deeper, so it went and the row stayed.
///
/// **What it depends on.** `PrescriptionSummary` for the words, `RestPrescription`
/// for a rest length, `PrescriptionLines` for a ramp, `PlannedExercise` from
/// Store and `MassUnit` from LiftingKit. It reads the store and writes nothing.
struct PrescribedExerciseRow: View {

    let exercise: PlannedExercise
    /// The lifter's display unit, so a prescribed load reads in the unit he
    /// reads everything else in.
    let unit: MassUnit

    /// Whether every set logged against this exercise is ticked. Absence of
    /// rows is not completion: an exercise nobody has opened has none.
    private var isComplete: Bool {
        let sets = exercise.loggedSets ?? []
        return !sets.isEmpty && sets.allSatisfy(\.isCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack {
                Text(exercise.displayName).font(.barbellTitle)
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Logged")
                }
            }
            // One line where one line holds it, stacked where it does not: at
            // accessibility text sizes "4 × 6-8 · RPE 7-8" and a rest no longer
            // fit side by side, and a prescription broken across a ragged pair
            // of columns is harder to read than two whole lines.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.standard) { prescription }
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: Spacing.tight) { prescription }
            }
            .font(.barbellSupport)
            .foregroundStyle(.secondary)

            if PrescriptionSummary.setsDiffer(in: exercise) {
                PrescriptionLines(sets: exercise.prescribedSets, unit: unit)
            }

            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.tight)
    }

    /// What the plan asks for, and how long it asks for between — the second
    /// drawn only when the plan prescribed one.
    @ViewBuilder
    private var prescription: some View {
        Label(PrescriptionSummary.text(for: exercise), systemImage: "repeat")
        if let rest = exercise.restSeconds {
            Label("\(RestPrescription.durationText(rest)) rest", systemImage: "timer")
        }
    }
}
