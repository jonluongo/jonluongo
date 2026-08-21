import SwiftUI
import LiftingKit

/// The editable body of one exercise's section: its set table, and the two notes
/// under it.
///
/// **The table is rows and nothing else.** Adding a set was a full-width button
/// under the last row, which made an occasional act a permanent fixture of the
/// table and put it beside the rows it was not part of. It is a menu item on
/// `ExerciseHeaderView` now, next to the warm-up it always resembled.
///
/// **Rest is not in here.** It was this card's first row, a full-width line
/// above the column headers, which made the card's most prominent statement the
/// one thing nobody came to read: the sets are the subject and the rest is a
/// detail of them.
///
/// **Every per-set statement reaches the lifter on the row it describes.** This
/// used to draw the whole prescription again as a numbered block above the
/// table, so the sentence about set four was off the top of the screen by the
/// time he reached set four.
///
/// **The only thing this writes is the record.** The prescription is read and
/// displayed, never edited.
///
/// **What it depends on.** `TrainingSlot` for the rows, `SetRowView` for each
/// one, and one previous performance for the field a prescription may leave
/// blank. It draws a movement performed on its own and one inside a group;
/// `paired` is the only difference.
struct ExerciseLogSection: View {

    let exercise: PlannedExercise
    /// This exercise's rows, in the order they are trained.
    let slots: [TrainingSlot]
    /// What has been performed of this movement today, or `nil` before anything
    /// has. It is where the lifter's own note lives.
    let performed: PerformedExercise?
    /// What he did on this movement last time, for the load field a
    /// prescription may leave blank.
    let previous: SnapshotPerformedExercise?
    var onRecord: (TrainingSlot, Mass?, Int?, Int?, Distance?) -> Void
    var onTakeBack: (TrainingSlot) -> Void
    /// Whether this movement is performed inside a group.
    var paired: Bool = false
    /// Whether the session has been marked finished.
    var isLocked: Bool = false

    var body: some View {
        VStack(spacing: Spacing.tight) {
            ForEach(slots) { slot in
                SetRowView(
                    slot: slot,
                    prescription: SetRowPrescription(slot: slot, previous: previous),
                    isLocked: isLocked,
                    onRecord: { load, reps, seconds, distance in
                        onRecord(slot, load, reps, seconds, distance)
                    },
                    onTakeBack: { onTakeBack(slot) })
                .padding(.horizontal, PanelMetrics.edge)
            }

            // At the foot rather than between the header and the table: a note
            // above the rows moved the first row down, so two exercises in one
            // session had their first row in different places. At the foot it is
            // additive — everything above it is where it always is.
            if let coachNote = exercise.coachNote, !coachNote.isEmpty {
                note(coachNote, isLifters: false)
            }
            // **His own, under the coach's, and in his own ink.** The two say
            // different things — the coach's is detail on the work, this is what
            // happened while doing it — so they are two lines rather than one,
            // and the darker of them is the one he wrote.
            if let mine = performed?.lifterNote, !mine.isEmpty {
                note(mine, isLifters: true)
            }
        }
    }

    /// A line at the foot of the panel: the coach's in support grey, the
    /// lifter's in ink. Neither is labelled — a note in a training log is either
    /// the plan's or his, and the one he typed is the one that reads like him.
    private func note(_ text: String, isLifters: Bool) -> some View {
        Text(text)
            .font(.supersetSupport)
            .foregroundStyle(isLifters ? Palette.ink : Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelMetrics.edge)
            .padding(.top, Spacing.standard)
    }
}
