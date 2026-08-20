import SwiftUI
import SwiftData
import LiftingKit

/// The editable body of one exercise's section inside `ActiveWorkoutView`: the
/// set table, and Claude's note under it when he wrote one. Split out to keep
/// `ActiveWorkoutView` focused on the workout's overall flow rather than
/// per-row mechanics. It draws a movement performed on its own and one
/// performed inside a group; `paired` is the only difference.
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
    /// Told which exercise, which set, and whether it was ticked or taken back.
    var onCompletionChanged: (PlannedExercise, LoggedSet, Bool) -> Void
    /// Whether these sets belong to a movement performed as part of a superset,
    /// which draws the rule down the panel's edge.
    var paired: Bool = false
    /// Whether the session has been marked finished, which closes the record
    /// until the lifter reopens it.
    var isLocked: Bool = false
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
        // **A stack, not a row each.** Every set used to be its own list row,
        // which is what made a panel a run of rows rather than an object: a
        // shadow cast by one of them landed on its neighbours, so a table of
        // sets could not be lifted the way a panel being chosen from is. The
        // whole exercise is one row now — the caller gives it one `panelRow`,
        // and every panel in the app carries the same fill, hairline, radius and
        // shadow.
        VStack(spacing: 0) {
            ForEach(Array(orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                let number = workingNumber(at: index)
                let prescribed = reading.prescription(
                    forWorkingNumber: number, isWarmup: set.isWarmup)
                // This row's own measure. A ramp may state a hold on one set and
                // reps on the next, and what a row writes is decided by what was
                // prescribed for it.
                let measure = WorkPrescription.measure(for: prescribed, in: exercise)
                SetRowView(
                    set: set,
                    identity: set.isWarmup ? .warmup : .working(number),
                    repTargetText: WorkPrescription.targetFigure(
                        for: prescribed?.repRange, measure: measure),
                    loadTargetText: loadPlaceholder(prescribed, number: number, set: set),
                    prescriptionDetail: PrescriptionSummary.detail(for: prescribed, in: exercise),
                    measure: measure,
                    unit: profile.displayUnit,
                    isLocked: isLocked,
                    onCompletionChanged: { onCompletionChanged(exercise, set, $0) }
                )
                .padding(.horizontal, PanelMetrics.edge)
                .padding(.vertical, SetTableMetrics.rowInsets.top)
                // Named so the screen can bring the next set of a group into
                // view. A row is identified by the set it logs, which is the
                // only thing about it that is stable.
                .id(set.persistentModelID)
            }

            // **Last, so the panel's shape does not depend on it.** The note is
            // optional and most exercises carry none; sitting between the name
            // and the table it moved the sets down on the ones that did, so two
            // exercises in the same session had their first row in different
            // places. At the foot it is additive: everything above it is where
            // it always is, and the note is simply there or not.
            if let notes = exercise.notes, !notes.isEmpty {
                note(notes, isLifters: false)
            }
            // **His own, under the coach's, and in his own ink.** The two say
            // different things — the coach's is extra detail on the work, and
            // this is what happened while doing it — so they are two lines
            // rather than one, and the darker of them is the one he wrote.
            if let mine = exercise.lifterNote, !mine.isEmpty {
                note(mine, isLifters: true)
            }
        }
    }

    /// A line at the foot of the panel: the coach's in support grey, the
    /// lifter's in ink. Neither is labelled — a note in a training log is
    /// either the plan's or his, and the one he typed is the one that reads
    /// like him.
    private func note(_ text: String, isLifters: Bool) -> some View {
        Text(text)
            .font(.supersetSupport)
            .foregroundStyle(isLifters ? Palette.ink : Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelMetrics.edge)
            .padding(.top, Spacing.standard)
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

    /// 1-based working-set number for the row at `index` (warmups don't count).
    private func workingNumber(at index: Int) -> Int {
        orderedSets.prefix(index + 1).filter { !$0.isWarmup }.count
    }
}
