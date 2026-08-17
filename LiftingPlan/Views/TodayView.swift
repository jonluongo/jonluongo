import SwiftUI
import SwiftData
import LiftingKit

/// The front door: which day the lifter is looking at, and the one thing there
/// is to do about it.
///
/// **What it does.** Draws a week of the block across the top, lets any day in
/// it be chosen by tap or by swipe, and answers what that day is — a session and
/// a way to begin it, the work already under way, a rest day, a block that has
/// not started, a block that is over, or a lifter with no block at all. It opens
/// on today every time, which is why the tab is still called Today.
///
/// **How it is used.** The first tab, inside a `NavigationStack`. There is no
/// large navigation title: it held one word above a hundred points of empty bar,
/// and the week strip earns that space instead. The block is reached by a link
/// rather than by a tab of its own, because the block is what a day is part of.
/// Nothing here writes to the store; the only thing it starts is logging.
///
/// **What it depends on.** `TodayInPlan` from Services, `WeekStrip` from
/// LiftingKit, `TrainingPlan` and `WorkoutDay` from Store, `TodayPhrasing` for
/// every line that is not a stored string, and the shared components.
///
/// ## The day being shown, and today
///
/// `chosen` is `nil` until the lifter swipes, and returns to `nil` whenever he
/// comes back to the app. Holding the absence rather than a copy of today's date
/// is what makes a phone left open overnight correct in the morning: there is no
/// stale date to go out of step, and *Today* is a state to return to rather than
/// a date to recompute.
struct TodayView: View {

    let profile: UserProfile

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// When "today" is, read once and refreshed when the app comes back to the
    /// screen. The moment the lifter looks at it is the moment it is re-read.
    @State private var now = Date()

    /// The day the lifter swiped or tapped to, or `nil` while the screen is
    /// still about today.
    @State private var chosen: Date?

    /// The session the logging screen is open on, or `nil`.
    @State private var openSession: WorkoutDay?

    private var plan: TrainingPlan? { plans.first }

    /// The start of today, in the lifter's own calendar.
    private var today: Date { calendar.startOfDay(for: now) }

    /// The start of the day the screen is showing.
    private var shown: Date { chosen ?? today }

    var body: some View {
        Group {
            if let plan {
                screen(plan)
            } else {
                noBlock
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { returnToToday }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
                // Coming back to the app is coming back to today. The screen is
                // named for it, and a lifter reopening his phone between sets
                // wants the day he is in, not the one he was reading about.
                chosen = nil
            }
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
    private func screen(_ plan: TrainingPlan) -> some View {
        let standing = TodayInPlan.resolve(plan, on: shown, calendar: calendar)
        switch standing.standing {
        case .undated, .unscheduled:
            noBlock
        default:
            List {
                Section { header(plan, standing.standing) }
                content(plan, standing)
            }
            .safeAreaInset(edge: .top, spacing: 0) { strip(plan) }
            .safeAreaInset(edge: .bottom) { action(plan, standing.standing) }
            // Simultaneous, so the list still scrolls: this only ever acts on a
            // gesture that ended up more sideways than it was long.
            .simultaneousGesture(swipe(plan))
        }
    }

    private var noBlock: some View {
        ContentUnavailableView {
            Label("No block yet", systemImage: "dumbbell")
        } description: {
            Text("Ask Claude for one.")
        }
    }

    // MARK: - The week

    /// The week the shown day falls in, pinned above everything else.
    ///
    /// Absent for a block no day can be chosen inside — see
    /// `TodayInPlan.selectableDays`. A strip that could not change the screen
    /// would be a control that does nothing.
    @ViewBuilder
    private func strip(_ plan: TrainingPlan) -> some View {
        if let reachable = reachableDays(plan) {
            WeekStripView(
                days: WeekStrip(calendar: calendar).week(containing: shown).map { date in
                    WeekStripDay(
                        date: date,
                        isToday: date == today,
                        isSelected: date == shown,
                        trains: TodayInPlan.prescribesSession(
                            in: plan, on: date, calendar: calendar),
                        isReachable: reachable.contains(date)
                    )
                },
                dayLine: TodayPhrasing.dayLine(shown),
                select: { choose($0) }
            )
        }
    }

    /// The way back, offered only once there is somewhere to come back from.
    @ToolbarContentBuilder
    private var returnToToday: some ToolbarContent {
        if chosen != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { withAnimation { chosen = nil } }
                    .accessibilityHint("Shows today again")
            }
        }
    }

    /// The days this screen will show, which is the block's own days plus today.
    ///
    /// Today is included even when it falls outside the block — before it starts
    /// or after it ends — because a screen that opens on a day it will not let
    /// you return to is a trap. Every day in this range resolves to something
    /// with words on it, which is the property that stops a swipe reaching a
    /// blank screen.
    private func reachableDays(_ plan: TrainingPlan) -> ClosedRange<Date>? {
        guard let span = TodayInPlan.selectableDays(in: plan, calendar: calendar) else {
            return nil
        }
        return min(span.lowerBound, today)...max(span.upperBound, today)
    }

    /// Left for the next day, right for the previous.
    ///
    /// A swipe has to travel further than the smallest thing it could have been
    /// aiming at, and end up more sideways than it was long, before it counts —
    /// otherwise a diagonal flick down a long session would change the day.
    private func swipe(_ plan: TrainingPlan) -> some Gesture {
        DragGesture(minimumDistance: TapTarget.minimum)
            .onEnded { drag in
                let sideways = drag.translation.width
                guard abs(sideways) > abs(drag.translation.height) else { return }
                step(sideways < 0 ? 1 : -1, in: plan)
            }
    }

    /// Moves one day, or stays put at the ends of the block. Nothing is clamped
    /// and nothing wraps: the strip simply stops, which is what a lifter feels
    /// as an edge.
    private func step(_ days: Int, in plan: TrainingPlan) {
        guard
            let reachable = reachableDays(plan),
            let moved = WeekStrip(calendar: calendar)
                .day(shown, steppedBy: days, within: reachable)
        else { return }
        choose(moved)
    }

    /// Shows a day, and forgets the choice again when the day chosen is today —
    /// so tapping today's column puts the *Today* button away, exactly as
    /// pressing it would.
    private func choose(_ date: Date) {
        withAnimation { chosen = date == today ? nil : date }
    }

    // MARK: - Header

    /// The block and the week, and the way into the block. One line, always in
    /// the same place, and it costs nothing when it is not tapped.
    ///
    /// It survives the week strip because the two say different things: the
    /// strip says which Wednesday, and this says which week of training that
    /// Wednesday belongs to — an ordinal and a label the calendar cannot show.
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
            TodaySessionSection(day: day, plan: plan)
            noteSection(plan)
        case .rest:
            TodayRestSection()
            noteSection(plan)
        case .beforeBlock(let days):
            TodayBeforeBlockSection(daysUntilStart: days)
            noteSection(plan)
        case .closed, .elapsed:
            TodayFinishedSection(plan: plan)
        case .undated, .unscheduled:
            EmptyView()
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

    /// Start, resume, or reopen — **on today, and only on today.**
    ///
    /// Another day's session is shown in full, because seeing what a day holds
    /// is what the strip is for, but it does not offer to be started. A block
    /// prescribes its sessions in an order; deciding to train Thursday's work on
    /// Tuesday is the lifter's to make, and it should not be one mis-swipe and
    /// one mis-tap away on a screen read one-handed. A finished session keeps
    /// its button, so a mis-tapped Finish or a weight typed wrong is not a dead
    /// end.
    ///
    /// Absent too for a session that prescribes nothing: a button that opens an
    /// empty logging screen is a promise the plan did not make.
    @ViewBuilder
    private func action(_ plan: TrainingPlan, _ standing: TodayInBlock.Standing) -> some View {
        if chosen == nil,
            let day = standing.session,
            let session = TodayInPlan.session(day, in: plan),
            !session.orderedExercises.isEmpty {
            let isDone = if case .finished = day.progress { true } else { false }
            PrimaryActionButton(
                title: TodayPhrasing.actionTitle(for: day.progress),
                systemImage: isDone ? "square.and.pencil" : "play.fill"
            ) {
                openSession = session
            }
            .padding(Spacing.section)
            .background(.bar)
        }
    }
}
