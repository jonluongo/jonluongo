import SwiftUI
import SwiftData
import LiftingKit

/// The editable body of one exercise's section inside `ActiveWorkoutView`:
/// notes, the prescribed rest, and the set table. Split out to keep
/// `ActiveWorkoutView` focused on the workout's overall flow rather than
/// per-row mechanics.
///
/// **The table is rows and nothing else.** Adding a set was a full-width button
/// under the last row, which made an occasional act a permanent fixture of the
/// table and put it beside the rows it was not part of. It is a menu item on
/// `ExerciseHeaderView` now, next to the warm-up it always resembled.
///
/// Weight is shown and entered in `profile.displayUnit`; `previousText` reads
/// the lifter's most recent performance on this exercise (keyed by
/// `exerciseID`, never by name) and converts it to that same unit.
///
/// **The only thing this section writes is the log.** The prescription — sets,
/// reps, rest — is read and displayed, never edited: a rest the lifter changed
/// in the gym would go out in the snapshot as though Claude had prescribed it,
/// and he would read his own plan back with a number he never wrote. The rest
/// line is a control now, but what it edits is the lifter's clock in
/// `RestPreferences`, which lives outside the store entirely; when his clock and
/// the prescription differ the line names both, so the screen never claims the
/// plan asked for his number.
///
/// **Every per-set statement reaches the lifter on the row it describes.** This
/// section used to draw the whole prescription again as a numbered block above
/// the table; the sentence about set four was off the top of the screen by the
/// time he reached set four. Each row now carries its own: its load and its reps
/// as the placeholders in its two fields, and its effort target and its note in
/// the line underneath. The numbered block still earns its place in
/// `PrescribedExerciseRow`, which states a session that has no rows yet.
struct ExerciseLogSection: View {
    let exercise: PlannedExercise
    let profile: UserProfile
    let plans: [TrainingPlan]
    var onDeleteSet: (LoggedSet, PlannedExercise) -> Void
    /// Told which exercise, and whether the set was ticked or taken back.
    var onCompletionChanged: (PlannedExercise, Bool) -> Void
    /// Opens this exercise's clock. Tapping the rest line is the whole of the
    /// rest control now — there is no timer button in the toolbar, because one
    /// button up there could not mean anything specific when every exercise
    /// prescribes its own rest.
    var onEditRest: (PlannedExercise) -> Void

    /// The lifter's own clock, which is not part of the plan and not in the
    /// store. Read here only to draw the line.
    @Environment(RestPreferences.self) private var restPreferences

    private var orderedSets: [LoggedSet] {
        (exercise.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }
    }

    /// What each row is shown besides the numbers the lifter types: what the
    /// plan asked of that set, and what he did on it last time. The same reader
    /// a row inside a group is built from.
    private var reading: SetRowPrescription {
        SetRowPrescription(exercise: exercise, plans: plans, unit: profile.displayUnit)
    }

    /// What the rest line says: the plan's rest, and the lifter's clock beside
    /// it whenever the two differ. `nil` when the plan prescribed no rest and
    /// the lifter has asked for nothing.
    private var restLine: String? {
        RestPrescription.line(
            prescribed: exercise.restSeconds,
            lifter: restPreferences.rest(for: exercise.exerciseID),
            timersEnabled: restPreferences.timersEnabled
        )
    }

    var body: some View {
        Group {
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }

            // Shown when the plan prescribed a rest, or when the lifter set a
            // clock of his own on an exercise it did not. Nothing is drawn when
            // neither is true, and nothing invites him to fill the gap in — the
            // menu is where a timer on an unprescribed exercise is asked for.
            if let restLine {
                Button {
                    onEditRest(exercise)
                } label: {
                    HStack(spacing: Spacing.tight) {
                        Label(restLine, systemImage: "timer")
                        Image(systemName: "chevron.right")
                            .font(.barbellLabel)
                    }
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: TapTarget.minimum, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(restLine)
                .accessibilityHint("Sets the rest timer for this exercise")
            }

            SetTableHeader(
                firstColumn: "SET", measure: reading.measure, unit: profile.displayUnit)

            ForEach(Array(orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                let number = workingNumber(at: index)
                let prescribed = reading.prescription(
                    forWorkingNumber: number, isWarmup: set.isWarmup)
                SetRowView(
                    set: set,
                    identity: set.isWarmup ? .warmup : .working(number),
                    previousText: reading.previousText(
                        workingIndex: number - 1, isWarmup: set.isWarmup),
                    repTargetText: RepPrescription.targetText(for: prescribed?.repRange),
                    loadTargetText: reading.loadTarget(prescribed),
                    prescriptionDetail: PrescriptionSummary.detail(for: prescribed, in: exercise),
                    intensity: EffortEntry.invitation(from: prescribed),
                    measure: reading.measure,
                    unit: profile.displayUnit,
                    onCompletionChanged: { onCompletionChanged(exercise, $0) }
                )
                .listRowBackground(set.isCompleted ? Color.green.opacity(0.12) : nil)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onDeleteSet(set, exercise) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// 1-based working-set number for the row at `index` (warmups don't count).
    private func workingNumber(at index: Int) -> Int {
        orderedSets.prefix(index + 1).filter { !$0.isWarmup }.count
    }
}
