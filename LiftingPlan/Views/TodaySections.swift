import SwiftUI
import LiftingKit

/// The sections the Today screen is assembled from, one per thing today can be.
///
/// **What they do.** Each is a `Section` and nothing more: `TodayView` decides
/// which of them today calls for, and each of these decides only how that one
/// thing reads. They live apart from the screen because the switch and the
/// prose were one file long enough to hide each other.
///
/// **How they are used.** Placed directly in the screen's `List`, in the order
/// the state calls for. They read the store and write nothing.
///
/// **What they depend on.** `TodayInPlan` for the stored session behind an
/// answer, `TodayPhrasing` for every line that is not a stored string, and the
/// shared components.

/// Today's session: what it is for, and every exercise it prescribes, one line
/// each.
///
/// The whole session is shown rather than the next exercise alone — a
/// prescribed session is something a lifter plans a gym trip around, and
/// whether the rack is still needed is a question the screen should already
/// have answered.
struct TodaySessionSection: View {

    let day: BlockDay
    let plan: TrainingPlan

    var body: some View {
        let session = TodayInPlan.session(day, in: plan)
        // The session's name is a row rather than a section header: a header is
        // drawn small, grey and uppercased, which is how a screen says "column
        // of a table", and this is the one thing on the screen.
        Section {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(TodayPhrasing.sessionTitle(day))
                    .font(.barbellTitle)
                if let shape = TodayPhrasing.sessionShape(
                    exercises: session?.orderedExercises.count ?? 0,
                    durationMinutes: session?.durationMinutes
                ) {
                    Text(shape)
                        .font(.barbellSupport)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Spacing.tight)

            if case .finished = day.progress {
                IconCircleRow(
                    systemImage: "checkmark", tint: .green, title: "Logged", subtitle: nil)
            }
            if let session {
                ForEach(session.orderedExercises) { exercise in
                    ExerciseLine(exercise: exercise)
                }
            } else {
                // The block moved underneath the answer. Said plainly rather
                // than guessed at with a neighbouring day's session.
                Text("This session is no longer in the record.")
                    .font(.barbellBody)
            }
        }
    }
}

/// A day the block prescribes nothing on.
///
/// Two days in five are this one, so it says what it is in the same type a
/// training day gets. Rest is what the block prescribes, not the absence of a
/// screen.
///
/// A *Next* section used to sit under this, naming the session after today,
/// because without it a rest day was a screen with one sentence on it. The week
/// strip above now says the same thing better: the next training day is a
/// marked column two thumbs away, in the context of the whole week, rather than
/// one line naming one day. The section was answering a question the header
/// already answers, so it went.
struct TodayRestSection: View {

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text("Rest day")
                    .font(.barbellTitle)
                Text("Nothing is prescribed today.")
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Spacing.tight)
        }
    }
}

/// A block that has not begun, and when it does.
struct TodayBeforeBlockSection: View {

    let daysUntilStart: Int

    var body: some View {
        Section {
            Text(TodayPhrasing.start(inDays: daysUntilStart))
                .font(.barbellTitle)
                .padding(.vertical, Spacing.tight)
        }
    }
}

/// A block that is over: what the record holds, and the one thing left to do
/// about it.
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
                    .font(.barbellTitle)
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

/// One prescribed exercise as a line: its name, and what the plan asks of it.
///
/// The per-set breakdown belongs to the logging screen; the front door states
/// the shape of the session and stops there.
private struct ExerciseLine: View {

    let exercise: PlannedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(exercise.displayName)
                .font(.barbellTitle)
            Text(PrescriptionSummary.text(for: exercise))
                .font(.barbellSupport)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.tight)
    }
}
