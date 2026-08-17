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

/// Which block the day belongs to, and which week of it.
///
/// **It is words and not a door.** This used to be a link into the block,
/// because the block had no other way in; the block is a tab now, so a chevron
/// here would be a second route to the same place on the screen that can least
/// afford a spare row. The words stayed: the strip above says which Wednesday,
/// and this says which week of training that Wednesday belongs to — an ordinal
/// and a label a calendar cannot show.
struct BlockHeaderSection: View {

    let plan: TrainingPlan
    let standing: TodayInBlock.Standing

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(Self.blockName(plan))
                    .font(.barbellTitle)
                if let line = Self.headerLine(plan, standing) {
                    Text(line)
                        .font(.barbellSupport)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Spacing.tight)
        }
    }

    /// What the plan called itself, or what it is for when it went unnamed.
    private static func blockName(_ plan: TrainingPlan) -> String {
        if !plan.title.isEmpty { return plan.title }
        if !plan.goal.isEmpty { return plan.goal }
        return "Block"
    }

    /// "Week 2 of 4 · Accumulation" while the day shown falls inside the block.
    /// Outside it there is no week to name, so the block's length is stated
    /// instead — and nothing at all before it starts, where the state below
    /// already says when that is.
    private static func headerLine(
        _ plan: TrainingPlan, _ standing: TodayInBlock.Standing
    ) -> String? {
        switch standing {
        case .session(let day): TodayPhrasing.weekLine(day.week)
        case .rest(let week): TodayPhrasing.weekLine(week)
        case .closed, .elapsed:
            plan.orderedWeeks.isEmpty
                ? nil
                : "\(plan.orderedWeeks.count) week\(plan.orderedWeeks.count == 1 ? "" : "s")"
        case .beforeBlock, .undated, .unscheduled: nil
        }
    }
}

/// The day's session in full: what it is for, and every exercise it
/// prescribes — the sets, the effort, the rest, the tempo, and a ramp written
/// out set by set where the plan wrote one.
///
/// The whole session is shown rather than the next exercise alone — a
/// prescribed session is something a lifter plans a gym trip around, and
/// whether the rack is still needed is a question the screen should already
/// have answered. It used to be a line each here and the rest of it one tap
/// deeper on a screen of its own; the deeper screen was the same session read
/// twice, so this took its contents and it went.
struct TodaySessionSection: View {

    let day: BlockDay
    let plan: TrainingPlan
    /// The lifter's display unit, so a prescribed load reads in the unit he
    /// reads everything else in.
    let unit: MassUnit
    /// Whether the screen is offering to start this session, which is true only
    /// on today. It decides nothing about the prescription — only whether the
    /// line explaining what the button does is worth printing.
    let startable: Bool

    private var session: WorkoutDay? { TodayInPlan.session(day, in: plan) }

    var body: some View {
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
                // Each row opens that exercise's record — which is where the
                // History tab went. A lifter reading tonight's bench press and
                // wondering what he benched last month is already looking at
                // the row that answers him.
                ForEach(session.orderedExercises) { exercise in
                    ExerciseHistoryLink(exercise: exercise, unit: unit)
                }
            } else {
                // The block moved underneath the answer. Said plainly rather
                // than guessed at with a neighbouring day's session.
                Text("This session is no longer in the record.")
                    .font(.barbellBody)
            }
        } footer: {
            if let restNote { Text(restNote) }
        }
    }

    /// What the button below will do, said once, and only where all three
    /// things it claims are true: there is a button, the session has not been
    /// started, and the plan prescribed rest somewhere in it.
    ///
    /// A session that prescribes no rest gets no sentence rather than a longer
    /// one explaining an absence — the app never decides how long to rest, and
    /// a paragraph saying so on every set of a bodyweight circuit is a wall in
    /// front of the one thing there is to do. It also goes once the lifter is
    /// under way: by then the answer is the screen he just came back from.
    private var restNote: String? {
        guard startable, case .notStarted = day.progress else { return nil }
        guard let session,
            session.orderedExercises.contains(where: { $0.restSeconds != nil })
        else { return nil }
        return """
            Tap Start to log this session set by set. Where the plan prescribes rest, \
            checking a set off runs that rest.
            """
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
