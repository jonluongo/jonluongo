import SwiftUI
import LiftingKit

/// The next workout in full: what it is for, and every exercise it prescribes —
/// the sets, the effort, the rest, the tempo, and a ramp written out set by set
/// where the plan wrote one.
///
/// The whole session is shown rather than the next exercise alone — a prescribed
/// session is something a lifter plans a gym trip around, and whether the rack is
/// still needed is a question the screen should already have answered.
///
/// It is handed the stored session directly. It used to take a day derived from
/// a calendar and look the stored one back up, which meant it also had to say
/// what it would do when the lookup failed; with no calendar in front of it there
/// is nothing to fail.
struct TodaySessionSection: View {

    let session: WorkoutDay
    /// The lifter's display unit, so a prescribed load reads in the unit he
    /// reads everything else in.
    let unit: MassUnit

    var body: some View {
        Section {
            // Each row opens that exercise's record — which is where the History
            // tab went. A lifter reading tonight's bench press and wondering
            // what he benched last month is already looking at the row that
            // answers him.
            ForEach(Array(session.entries.enumerated()), id: \.element.id) { index, entry in
                Group {
                    switch entry {
                    case .exercise(let exercise):
                        ExerciseDetailLink(exercise: exercise, unit: unit)
                    case .group(let group):
                        PrescribedGroupRows(group: group, unit: unit)
                    }
                }
                .panelRow(.at(index, of: session.entries.count))
                .listRowInsets(EdgeInsets(
                    top: Spacing.tight, leading: SetTableMetrics.contentInset,
                    bottom: Spacing.tight, trailing: SetTableMetrics.contentInset))
                // No rules between rows: the gap and the names say where one
                // exercise ends and the next begins.
                .listRowSeparator(.hidden)
            }
        } header: {
            header
        }
    }

    /// The workout's name, above the card rather than inside it.
    ///
    /// It was the card's first row, divided from the exercises by the same
    /// hairline that divides them from each other — so the thing naming the
    /// session was drawn as one more item in the list of exercises, and read
    /// like one. A section header sits outside the card, which is where a
    /// heading belongs and what makes the card beneath it read as its contents.
    ///
    /// `textCase(nil)` and the title ramp undo the small grey capitals a header
    /// is drawn in by default — that styling says "column of a table", and this
    /// is the one thing on the screen. The colour is stated as `Color.primary`
    /// rather than as `.primary`: a section header sets its own foreground in
    /// the environment, and the hierarchical shorthand resolved against that
    /// rather than replacing it, so the heading rendered lighter than the
    /// exercises underneath it — a title less prominent than the list it titles.
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(TodayPhrasing.sessionTitle(focus: session.focus, weekday: session.weekday))
                .font(.barbellHeading)
                .foregroundStyle(Color.primary)
            if let shape = TodayPhrasing.sessionShape(
                exercises: session.orderedExercises.count,
                durationMinutes: session.durationMinutes
            ) {
                Text(shape)
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.top, Spacing.snug)
        .padding(.bottom, Spacing.standard)
        .listRowInsets(EdgeInsets(
            top: 0, leading: Spacing.section, bottom: 0, trailing: Spacing.section))
    }
}

/// A block with no workout left in it: what the record holds, and the one thing
/// left to do about it.
///
/// The count is a count and not a score — nothing here decides whether it was
/// enough. The app cannot reach the coach, so it says who can.
struct TodayFinishedSection: View {

    let plan: TrainingPlan

    var body: some View {
        let days = plan.orderedWeeks.flatMap { $0.orderedDays }
        Section {
            VStack(alignment: .leading, spacing: Spacing.snug) {
                Text("Block finished")
                    .font(.barbellHeading)
                if let record = TodayPhrasing.recordLine(
                    finished: days.filter { $0.completedAt != nil }.count,
                    prescribed: days.count
                ) {
                    Text(record)
                        .font(.barbellSupport)
                        .foregroundStyle(.secondary)
                }
                Text("Ask Claude for the next one.")
                    .font(.barbellBody)
            }
            .padding(.vertical, Spacing.tight)
        }
    }
}
