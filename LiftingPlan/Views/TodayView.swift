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

    /// The session the logging screen is open on, or `nil`.
    @State private var openSession: WorkoutDay?

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

    /// The workout the button will start: the one swiped to, or the first left
    /// when nothing has been swiped to — and the first again whenever the one he
    /// had chosen leaves the week, which is what finishing it does.
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
        .fullScreenCover(item: $openSession) { session in
            ActiveWorkoutView(day: session, profile: profile)
        }
    }

    @ViewBuilder
    private func screen(_ plan: TrainingPlan) -> some View {
        if let selected {
            // One page per workout left in the week. The dots are drawn only
            // where there is more than one, because an indicator under a single
            // page says a choice exists that does not.
            TabView(selection: $chosen) {
                ForEach(remaining) { workout in
                    List {
                        PageTitle("Home")
                        TodaySessionSection(session: workout, unit: profile.displayUnit)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Palette.surface)
                    .tag(Optional(workout.persistentModelID))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: remaining.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            // Stated because a pager does not hand its background up the way a
            // list does: the navigation bar behind the title drew white over
            // grouped-grey content, a seam across the top of the screen.
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { action(selected) }
        } else {
            // Every session logged, or a block with nothing in it. Both read the
            // same to a lifter: there is no next workout, and the next one comes
            // from Claude.
            List {
                PageTitle("Home")
                TodayFinishedSection(plan: plan)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
        }
    }

    /// Start, or pick up where the session was left — whichever page he is on.
    /// A workout with prescribed exercises always has one: `remaining` never
    /// holds an empty session, so there is no button here that opens a screen
    /// with nothing on it.
    private func action(_ workout: WorkoutDay) -> some View {
        PrimaryActionButton(
            title: TodayPhrasing.actionTitle(for: TodayInPlan.progress(of: workout)),
            systemImage: "play.fill"
        ) {
            openSession = workout
        }
        .padding(Spacing.section)
        .background(Palette.surface)
    }
}
