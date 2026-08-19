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
/// it where no load was — in the line underneath. The numbered block that used
/// to state a session before it had rows went with the browsing screens that
/// drew it.
struct ExerciseLogSection: View {
    let exercise: PlannedExercise
    let profile: UserProfile
    let plans: [TrainingPlan]
    var onDeleteSet: (LoggedSet, PlannedExercise) -> Void
    /// Told which exercise, and whether the set was ticked or taken back.
    /// Told which exercise, which set, and whether it was ticked or taken back.
    var onCompletionChanged: (PlannedExercise, LoggedSet, Bool) -> Void
    /// Whether these sets belong to a movement performed as part of a superset,
    /// which draws the rule down the panel's edge.
    var paired: Bool = false
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
            ForEach(Array(orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                let number = workingNumber(at: index)
                let prescribed = reading.prescription(
                    forWorkingNumber: number, isWarmup: set.isWarmup)
                SetRowView(
                    set: set,
                    identity: set.isWarmup ? .warmup : .working(number),
                    repTargetText: RepPrescription.targetText(for: prescribed?.repRange),
                    loadTargetText: loadPlaceholder(prescribed, number: number, set: set),
                    prescriptionDetail: PrescriptionSummary.detail(for: prescribed, in: exercise),
                    measure: reading.measure,
                    unit: profile.displayUnit,
                    onCompletionChanged: { onCompletionChanged(exercise, set, $0) }
                )
                // The ground is the *panel's*, not the row's. A wash behind each
                // finished row was tried and killed — it striped the table as
                // sets were ticked, two statements of one fact with the louder
                // of them a second colour across every row. What the panel says
                // is whether the exercise is done, which is one fact and changes
                // once.
                .panelRow(
                    index == orderedSets.count - 1 && !hasNote ? .last : .middle,
                    insets: SetTableMetrics.rowInsets, paired: paired,
                    isRecorded: exercise.isFullyLogged)
                // No rules between rows. Each row already carries a ruled cell
                // under the two fields it is typed into, and a full-width line
                // on top of that was the table drawn twice — the gap and the
                // figures say where one set ends and the next begins.
                .listRowSeparator(.hidden)
                // Named so the screen can bring the next set of a group into
                // view. A row is identified by the set it logs, which is the
                // only thing about it that is stable.
                .id(set.persistentModelID)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onDeleteSet(set, exercise) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            // **Last, so the panel's shape does not depend on it.** The note is
            // optional and most exercises carry none; sitting between the name
            // and the table it moved the sets down on the ones that did, so two
            // exercises in the same session had their first row in different
            // places. At the foot it is additive: everything above it is where
            // it always is, and the note is simply there or not.
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.supersetSupport)
                    .foregroundStyle(Palette.muted)
                    .panelRow(
                        .last, insets: PanelMetrics.noteInsets,
                        paired: paired, isRecorded: exercise.isFullyLogged)
                    .listRowSeparator(.hidden)
            }
        }
    }

    /// What an empty weight field shows: the load the plan prescribed, and
    /// failing that what he lifted on this set last time. Claude's figure always
    /// wins; the ghost only fills a field that would otherwise be blank.
    private func loadPlaceholder(
        _ prescribed: SetPrescription?, number: Int, set: LoggedSet
    ) -> String {
        let target = reading.loadTarget(prescribed)
        guard target.isEmpty else { return target }
        return reading.previousLoad(workingIndex: number - 1, isWarmup: set.isWarmup)
    }

    /// Where a row sits in the panel. The note, when Claude wrote one, is the
    /// top of it; without one the first set is.
    private static func position(_ index: Int, of count: Int, hasNote: Bool) -> PanelPosition {
        if index == count - 1 { return index == 0 && !hasNote ? .only : .last }
        return index == 0 && !hasNote ? .first : .middle
    }

    /// 1-based working-set number for the row at `index` (warmups don't count).
    private func workingNumber(at index: Int) -> Int {
        orderedSets.prefix(index + 1).filter { !$0.isWarmup }.count
    }
}
