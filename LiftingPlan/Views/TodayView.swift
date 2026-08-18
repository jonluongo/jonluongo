import SwiftUI
import SwiftData
import LiftingKit

/// The front door: the next workout in the block, and the one thing there is to
/// do about it.
///
/// **What it does.** Shows the workouts left in the week the lifter is on, one
/// per page, and offers to start whichever he has swiped to. Three states and no
/// more — no block, a week with workouts left in it, or a block whose sessions
/// have all been logged.
///
/// **He chooses which one, not the app.** It used to show the first unlogged
/// session and only that, which quietly decided the order of his week for him:
/// a lifter who wanted legs on Monday had no way to say so, and the screen would
/// have sat on Push until he trained it. The block prescribes what the week
/// holds and Claude decides that; which of them he does today is his, and it was
/// never the app's to hold. When one workout is left there is one page and
/// nothing to swipe, which is the same statement made by the absence of a
/// choice.
///
/// **There is no calendar here, deliberately.** A week strip used to sit across
/// the top, pinned to a start date the app itself invented — `PlanImporter`
/// stamped the block with whatever moment the file happened to arrive, and every
/// dot, every marked column and every "rest day" was drawn on top of a fact
/// nobody had decided. It also showed *intent* while the log records *fact*: a
/// session carries the instant it was actually finished, which is what Claude
/// reads and what a lifter actually did. The calendar could only ever disagree
/// with that, so it went, and with it the question of what happens when a
/// Tuesday session gets trained on a Wednesday. Sessions are trained in the
/// order the block prescribes them, and the record says when.
///
/// **How it is used.** The first tab. It carries a `NavigationStack` so an
/// exercise can open its own record. Nothing here writes to the store; the only
/// thing it starts is logging.
///
/// **What it depends on.** `TrainingPlan` and `WorkoutDay` from Store,
/// `TodayInPlan` for how far a session has got, `TodayPhrasing` for the word on
/// the button, and the shared components.
struct TodayView: View {

    let profile: UserProfile

    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// Which of the two screens behind the menu is open, if either.
    @State private var elsewhere: Elsewhere?

    /// The page he has swiped to, or `nil` before he has swiped at all — which
    /// shows the first workout left in the week.
    @State private var chosen: PersistentIdentifier?

    private var plan: TrainingPlan? { plans.first }

    /// The workouts left in the week the lifter is on: every session of the
    /// earliest week that still holds one, that has not been logged.
    ///
    /// A day the block prescribes no exercises on is passed over rather than
    /// shown — it is not a workout, and it will never be logged, so offering it
    /// would be offering a page with nothing to do on it. That is a reading of
    /// the block, not a decision about it: what to train is still entirely
    /// Claude's, and this only finds what is left of what he wrote.
    private var remaining: [WorkoutDay] {
        guard let week = plan?.orderedWeeks.first(where: { !Self.left(in: $0).isEmpty }) else {
            return []
        }
        return Self.left(in: week)
    }

    private static func left(in week: TrainingWeek) -> [WorkoutDay] {
        week.orderedDays.filter { $0.completedAt == nil && !$0.orderedExercises.isEmpty }
    }

    /// The workout on screen: the one swiped to, or the first left when nothing
    /// has been swiped to — and the first again whenever the one he had chosen
    /// leaves the week, which is what finishing it does.
    private var selected: WorkoutDay? {
        remaining.first { $0.persistentModelID == chosen } ?? remaining.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    screen(plan)
                } else {
                    NoBlockView()
                }
            }
            // No navigation bar at all, and the title drawn as the first row of
            // the content instead.
            //
            // A large title only collapses when it is attached to the scroll
            // view it should track. The scrolling here happens inside the
            // pager's pages while the title sat on the view holding the pager,
            // so it had nothing to follow: it stood permanently large in a band
            // with the full large-title inset above it, about fifty points
            // lower than the same word sits in Podcasts, and no amount of
            // trimming underneath was going to move it. Drawn as a row it sits
            // where it should and scrolls away with everything else, which is
            // the behaviour the bar could not give it.
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $elsewhere) { destination in
            NavigationStack {
                switch destination {
                case .blocks: PlansView(profile: profile)
                case .account: AccountView(profile: profile)
                }
            }
        }
    }

    /// The two screens that are not the session: the block he is in, and the
    /// record Claude keeps. They were tabs, opened roughly never and charging
    /// ninety points of every screen for the privilege.
    enum Elsewhere: String, Identifiable {
        case blocks
        case account

        var id: String { rawValue }
    }

    @ViewBuilder
    private func screen(_ plan: TrainingPlan) -> some View {
        // The title sits above the pager rather than inside its pages. Inside,
        // it swiped sideways along with the workouts — and the name of the
        // screen is not one of the things being swiped between.
        VStack(alignment: .leading, spacing: 0) {
            header
            pages(plan)
        }
        // Stated, because the title is no longer inside a list and so inherits
        // nothing from one: it drew on white above grouped-grey content, a band
        // across the top of the screen.
        .background(Palette.surface)
    }

    /// The session's own name, and the way to everything that is not it.
    ///
    /// The name is the page's title because the session *is* the page — there
    /// is no longer a screen called Home standing in front of it.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                // The title states the screen's one subject. With no session
                // left it is the state of the block, not the absence of a
                // workout: "No workout" was the negative of a fact the section
                // beneath then stated positively, so the screen carried two
                // headings for one thing and led with the emptier of them.
                Text(selected.map {
                    TodayPhrasing.sessionTitle(focus: $0.focus, weekday: $0.weekday)
                } ?? "Block finished")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: Spacing.snug) {
                    if let shape {
                        Text(shape)
                            .font(.barbellSupport)
                            .foregroundStyle(Palette.muted)
                    }
                    // How long he has been training, beside what he is training
                    // — the one line on the screen that is not part of the log.
                    // It counts from the first ticked set, so it says nothing
                    // until he has done something.
                    if let startedAt = selected?.startedAt {
                        SessionClock(startedAt: startedAt, finishedAt: selected?.completedAt)
                    }
                }
            }
            Spacer()
            Menu {
                Button("Block", systemImage: "square.stack") { elsewhere = .blocks }
                Button("Account", systemImage: "person.crop.circle") { elsewhere = .account }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.barbellBody)
                    .foregroundStyle(Palette.muted)
                    .frame(width: TapTarget.minimum, height: TapTarget.minimum, alignment: .trailing)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Block and account")
        }
        .padding(.horizontal, PanelMetrics.inset)
        .padding(.top, Spacing.snug)
        .padding(.bottom, Spacing.standard)
    }

    /// What the session on screen amounts to, or nothing when there is none.
    ///
    /// The unit used to be here. It was a column heading before that, and moving
    /// it up was compensation for a deletion that was itself compensation — a
    /// lifter knows whether he counts in pounds or kilos, it never changes
    /// without him changing it, and Account states it where it is set. A word on
    /// every screen that tells him something he has never once needed to be told
    /// is a word that has not earned its place.
    private var shape: String? {
        guard let selected else { return nil }
        return TodayPhrasing.sessionShape(
            exercises: selected.orderedExercises.count,
            durationMinutes: selected.durationMinutes)
    }

    @ViewBuilder
    private func pages(_ plan: TrainingPlan) -> some View {
        if selected != nil {
            // One page per workout left in the week, each of them a card that
            // is itself the control — there is no separate start button, and no
            // page sizes to its own contents, so swiping does not resize the
            // thing under the thumb. The dots are drawn only where there is
            // more than one, because an indicator under a single page says a
            // choice exists that does not.
            TabView(selection: $chosen) {
                ForEach(remaining) { workout in
                    ActiveWorkoutView(day: workout, profile: profile)
                        .tag(Optional(workout.persistentModelID))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: remaining.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            // Stated because a pager does not hand its background up the way a
            // list does: the navigation bar behind the title drew white over
            // grouped-grey content, a seam across the top of the screen.
            .background(Palette.surface)
        } else {
            // Every session logged, or a block with nothing in it. Both read the
            // same to a lifter: there is no next workout, and the next one comes
            // from Claude.
            List {
                TodayFinishedSection(plan: plan)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
        }
    }


}
