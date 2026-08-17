import SwiftUI
import LiftingKit

/// One prescribed exercise, read before it is trained: its name and what the
/// plan asks of it.
///
/// **What it does.** States the plan and nothing else. Inside a group it is
/// prefixed with the `A1` / `A2` the group's header legends, and nothing else
/// about it changes. The sets it asks for and
/// the effort it asks for sit beside a repeat glyph, and the rest it prescribes
/// beside a clock — and the rest is absent when the plan prescribed none, since
/// a session that asks for no rest shows none rather than `0s`.
///
/// **A ramp gets the same shape as everything else: a name and one line.** It
/// used to state its count and then list its sets beneath, five rows where its
/// neighbours took two, so one exercise in the list read as a different kind of
/// object from the rest. `PrescriptionSummary` spans it instead — `3 × 5 · 60-80
/// kg` says these differ and how far without naming a figure no set of it has.
/// The sets themselves are not lost: every one of them reaches the lifter in
/// full on the logging screen, on the row it is lifted on, which is the only
/// screen where knowing set four's load in advance is worth a row of its own.
///
/// **Tempo is not here.** It is a per-rep instruction, and the place it is
/// needed is under the bar: `ExerciseHeaderView` states it on the logging
/// screen. A third column of it here cost a line on every exercise to answer a
/// question nobody asks while deciding whether to go to the gym.
///
/// **Neither is the coach's note.** This row says what the session *is* — the
/// movement, the sets, the reps, the effort and the rest. What Claude *said*
/// about the movement is an instruction for the moment the bar is loaded, and
/// it reaches the lifter there: `ExerciseLogSection` and `SupersetHeaderView`
/// state the exercise's note on the logging screen, and `SetDetailLine` states
/// a note about one set on that set's own row. Drawn here as well, a session of
/// six exercises opened as a wall of prose in front of a lifter deciding
/// whether to start.
///
/// **Nor is whether it has been logged.** This row used to carry a green
/// circled check when every set of the exercise was ticked, on the same screen
/// as the green circled check beside the day — one badge making two different
/// claims, which read as one claim nobody could pin down. The day-level mark is
/// the one a screen of prescriptions is for; which of Monday's six exercises
/// got finished is a question asked under the bar, and `ExerciseLogSection`
/// answers it there, set by set.
///
/// **How it is used.** The Today screen draws one per exercise of the day it is
/// showing. It was the session preview screen's row; that screen showed the same
/// session Today now shows, one tap deeper, so it went and the row stayed.
///
/// **What it depends on.** `PrescriptionSummary` for the words,
/// `RestPrescription` for a rest length, `PlannedExercise` from Store and
/// `MassUnit` from LiftingKit. It reads the store and writes nothing.
struct PrescribedExerciseRow: View {

    let exercise: PlannedExercise
    /// The lifter's display unit, so a prescribed load reads in the unit he
    /// reads everything else in.
    let unit: MassUnit
    /// How this movement is written within its group — `A1`, `A2` — or `nil`
    /// when it is performed on its own, which draws exactly the row it always
    /// drew. The common case pays nothing for the rare one.
    var notation: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack {
                if let notation {
                    Text(notation)
                        .font(.barbellLabel)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(notation),")
                }
                Text(exercise.displayName).font(.barbellTitle)
                Spacer()
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
        }
        .padding(.vertical, Spacing.tight)
    }

    /// What the plan asks for, and how long it asks for between — the second
    /// drawn only when the plan prescribed one.
    @ViewBuilder
    private var prescription: some View {
        Label(PrescriptionSummary.text(for: exercise, unit: unit), systemImage: "repeat")
        // A movement inside a group states no rest of its own: the rest comes
        // after the round, and the group's own line has already said how long.
        // Repeating it here would read as this movement asking for it alone.
        if let rest = exercise.restSeconds, notation == nil {
            Label("\(RestPrescription.durationText(rest)) rest", systemImage: "timer")
        }
    }
}
