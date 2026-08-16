import SwiftUI
import SwiftData
import LiftingKit

/// The front door: what today is, and the one thing there is to do about it.
///
/// **What it does.** Asks `TodayInPlan` where today falls in the current block
/// and draws the one screen that answer calls for — today's session and a way
/// to begin it, the work already under way, a rest day and what follows it, a
/// block that has not started, a block that is over, or a lifter with no block
/// at all. It replaces the Plan tab, which rendered every week of a block
/// identically and left the lifter to work out which one he was in.
///
/// **How it is used.** The first tab, inside a `NavigationStack`. The header is
/// a link into `BlockView` rather than a tab of its own: the block is what
/// today is part of, so it sits behind today. Nothing here writes to the store;
/// the only thing it starts is the logging screen.
///
/// **What it depends on.** `TodayInPlan` from Services, `TrainingPlan` and
/// `WorkoutDay` from Store, `TodayPhrasing` for every line that is not a stored
/// string, and the shared components.
struct TodayView: View {

    let profile: UserProfile

    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// When "today" is, read once and refreshed when the app comes back to the
    /// screen. A phone left open overnight would otherwise still be showing
    /// yesterday, and the moment the lifter looks at it is the moment it is
    /// re-read.
    @State private var now = Date()

    /// The session the logging screen is open on, or `nil`.
    @State private var openSession: WorkoutDay?

    private var plan: TrainingPlan? { plans.first }

    var body: some View {
        Group {
            if let plan {
                today(plan, TodayInPlan.resolve(plan, on: now))
            } else {
                noBlock
            }
        }
        .navigationTitle("Today")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .fullScreenCover(item: $openSession) { session in
            ActiveWorkoutView(day: session, profile: profile)
        }
    }

    /// A block nothing can be placed against — one with no start date, or with
    /// no weeks — is not a block the lifter has, so it reads as not having one.
    /// Saying "Week 1" over a plan that states neither would be the app
    /// inventing the fact that is missing.
    @ViewBuilder
    private func today(_ plan: TrainingPlan, _ standing: TodayInBlock) -> some View {
        switch standing.standing {
        case .undated, .unscheduled:
            noBlock
        default:
            List {
                Section { header(plan, standing.standing) }
                content(plan, standing)
            }
            .safeAreaInset(edge: .bottom) { action(plan, standing.standing) }
        }
    }

    private var noBlock: some View {
        ContentUnavailableView {
            Label("No block yet", systemImage: "dumbbell")
        } description: {
            Text("Ask Claude for one.")
        }
    }

    // MARK: - Header

    /// The block and the week, and the way into the block. Fitbod's "My Plan ›"
    /// rather than a calendar tab: one line, always in the same place, and it
    /// costs nothing when it is not tapped.
    private func header(
        _ plan: TrainingPlan, _ standing: TodayInBlock.Standing
    ) -> some View {
        NavigationLink {
            BlockView(
                plan: plan, profile: profile,
                currentWeekOrdinal: Self.currentOrdinal(standing)
            )
        } label: {
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

    /// "Week 2 of 4 · Accumulation" while today falls inside the block. Outside
    /// it there is no week to name, so the block's length is stated instead —
    /// and nothing at all before it starts, where the state below already says
    /// when that is.
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

    private static func currentOrdinal(_ standing: TodayInBlock.Standing) -> Int? {
        switch standing {
        case .session(let day): day.week.ordinal
        case .rest(let week): week.ordinal
        default: nil
        }
    }

    // MARK: - The state

    @ViewBuilder
    private func content(_ plan: TrainingPlan, _ standing: TodayInBlock) -> some View {
        switch standing.standing {
        case .session(let day):
            sessionSection(day, in: plan)
            if day.progress.isFinished, let next = standing.upcoming {
                nextSection(next, in: plan)
            }
            noteSection(plan)
        case .rest:
            restSection
            if let next = standing.upcoming { nextSection(next, in: plan) }
            noteSection(plan)
        case .beforeBlock(let days):
            Section {
                Text(TodayPhrasing.start(inDays: days))
                    .font(.barbellTitle)
                    .padding(.vertical, Spacing.tight)
            }
            if let next = standing.upcoming { nextSection(next, in: plan) }
            noteSection(plan)
        case .closed, .elapsed:
            finishedSection(plan)
        case .undated, .unscheduled:
            EmptyView()
        }
    }

    /// Today's session: what it is for, and every exercise it prescribes, one
    /// line each. The whole session is shown rather than the next exercise
    /// alone — a prescribed session is something the lifter plans a gym trip
    /// around, and whether the rack is still needed is a question the screen
    /// should already have answered.
    @ViewBuilder
    private func sessionSection(_ day: BlockDay, in plan: TrainingPlan) -> some View {
        let session = TodayInPlan.session(day, in: plan)
        Section {
            if case .finished = day.progress {
                IconCircleRow(
                    systemImage: "checkmark", tint: .green,
                    title: "Logged", subtitle: nil
                )
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
        } header: {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(TodayPhrasing.sessionTitle(day))
                    .font(.barbellTitle)
                    .foregroundStyle(.primary)
                if let shape = TodayPhrasing.sessionShape(
                    exercises: session?.orderedExercises.count ?? 0,
                    durationMinutes: session?.durationMinutes
                ) {
                    Text(shape)
                        .font(.barbellSupport)
                        .foregroundStyle(.secondary)
                }
            }
            .textCase(nil)
            .padding(.bottom, Spacing.snug)
        }
    }

    /// Two days in five are this one, so it says what it is and what follows,
    /// in the same type a training day gets. Rest is what the block prescribes
    /// today, not the absence of a screen.
    private var restSection: some View {
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

    /// The next session the block prescribes, and the way into it.
    @ViewBuilder
    private func nextSection(_ next: BlockDay, in plan: TrainingPlan) -> some View {
        let session = TodayInPlan.session(next, in: plan)
        Section("Next") {
            if let session {
                NavigationLink {
                    SessionDetailView(day: session, profile: profile)
                } label: {
                    IconCircleRow(
                        systemImage: "dumbbell.fill", tint: .accentColor,
                        title: TodayPhrasing.nextLine(for: next, from: now),
                        subtitle: TodayPhrasing.sessionShape(
                            exercises: session.orderedExercises.count,
                            durationMinutes: session.durationMinutes)
                    )
                }
            } else {
                Text(TodayPhrasing.nextLine(for: next, from: now))
                    .font(.barbellBody)
            }
        }
    }

    /// A block that is over: what the record holds, and the one thing left to
    /// do about it. The app cannot reach the coach, so it says who can.
    private func finishedSection(_ plan: TrainingPlan) -> some View {
        let days = plan.orderedWeeks.flatMap { $0.orderedDays }
        return Section {
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

    /// The coach's words, while the block is one the lifter is in. Absent when
    /// he wrote none — an empty section would read as a note that failed to
    /// arrive.
    @ViewBuilder
    private func noteSection(_ plan: TrainingPlan) -> some View {
        if let note = plan.notes, !note.isEmpty {
            Section { CoachNoteView(note: note) }
        }
    }

    // MARK: - The one thing to do

    /// Start, or resume where the work stopped. Absent for a session already
    /// finished and for one that prescribes nothing — a button that opens an
    /// empty logging screen is a promise the plan did not make.
    @ViewBuilder
    private func action(_ plan: TrainingPlan, _ standing: TodayInBlock.Standing) -> some View {
        if let day = standing.session,
            let title = TodayPhrasing.actionTitle(for: day.progress),
            let session = TodayInPlan.session(day, in: plan),
            !session.orderedExercises.isEmpty {
            PrimaryActionButton(title: title, systemImage: "play.fill") {
                openSession = session
            }
            .padding(Spacing.section)
            .background(.bar)
        }
    }
}

/// One prescribed exercise as a line: its name, and what the plan asks of it.
///
/// The full per-set breakdown belongs to the logging screen; the front door
/// states the shape of the session and stops there.
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
