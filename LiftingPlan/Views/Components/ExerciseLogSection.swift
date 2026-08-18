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
/// reps, rest — is read and displayed, never edited.
///
/// **Rest is not in here.** It was this card's first row, a full-width line
/// above the column headers, which made the card's most prominent statement the
/// one thing on it nobody came to read: the sets are the subject and the rest is
/// a detail of them. It is a clause in the header's line now, and the clock is
/// edited from the header's menu, where the other things done to a whole
/// exercise already live.
///
/// **Every per-set statement reaches the lifter on the row it describes.** This
/// section used to draw the whole prescription again as a numbered block above
/// the table; the sentence about set four was off the top of the screen by the
/// time he reached set four. Each row now carries its own: its load and its reps
/// as the placeholders in its two fields, and its note — and the effort asked of
/// it where no load was — in the line underneath. The numbered block still earns
/// its place in `PrescribedExerciseRow`, which states a session that has no rows
/// yet.
struct ExerciseLogSection: View {
    let exercise: PlannedExercise
    let profile: UserProfile
    let plans: [TrainingPlan]
    var onDeleteSet: (LoggedSet, PlannedExercise) -> Void
    /// Told which exercise, and whether the set was ticked or taken back.
    var onCompletionChanged: (PlannedExercise, Bool) -> Void
    /// Whether Claude wrote anything about this exercise, which decides which
    /// row is the top of the panel.
    private var hasNote: Bool {
        (exercise.notes.map { !$0.isEmpty }) ?? false
    }

    private var orderedSets: [LoggedSet] {
        (exercise.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }
    }

    /// What each row is shown besides the numbers the lifter types: what the
    /// plan asked of that set, and what he did on it last time. The same reader
    /// a row inside a group is built from.
    private var reading: SetRowPrescription {
        SetRowPrescription(exercise: exercise, plans: plans, unit: profile.displayUnit)
    }

    var body: some View {
        Group {
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.barbellSupport)
                    .foregroundStyle(Palette.muted)
                    .panelRow(.first)
                    .listRowSeparator(.hidden)
            }

            SetTableHeader(
                firstColumn: "SET", measure: reading.measure, unit: profile.displayUnit)
                .panelRow(hasNote ? .middle : .first, insets: SetTableMetrics.headerInsets)
                .listRowSeparator(.hidden)

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
                    measure: reading.measure,
                    unit: profile.displayUnit,
                    onCompletionChanged: { onCompletionChanged(exercise, $0) }
                )
                // No wash behind a finished row. The filled square is the mark
                // that it happened, and a pale green band the width of the
                // screen said the same thing far louder — two statements of one
                // fact, and the louder of them a second colour across the whole
                // table. Chanel's rule: take one thing off.
                .panelRow(
                    index == orderedSets.count - 1 ? .last : .middle,
                    insets: SetTableMetrics.rowInsets)
                // No rules between rows. Each row already carries a ruled cell
                // under the two fields it is typed into, and a full-width line
                // on top of that was the table drawn twice — the gap and the
                // figures say where one set ends and the next begins.
                .listRowSeparator(.hidden)
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
