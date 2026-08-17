import SwiftUI
import SwiftData
import LiftingKit

/// The front door: the next workout in the block, and the one thing there is to
/// do about it.
///
/// **What it does.** Finds the first session the block prescribes that has not
/// been logged, shows it in full, and offers to start it. Three states and no
/// more — no block, a workout waiting, or a block whose sessions have all been
/// logged.
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

    private var plan: TrainingPlan? { plans.first }

    /// The next workout: the first session in the block that has not been
    /// logged.
    ///
    /// A day the block prescribes no exercises on is passed over rather than
    /// shown — it is not a workout, and it will never be logged, so stopping on
    /// it would strand the screen there forever. That is a reading of the block,
    /// not a decision about it: what to train is still entirely Claude's, and
    /// this only finds where the lifter has got to in what was written.
    private var nextWorkout: WorkoutDay? {
        plan?.orderedWeeks
            .flatMap { $0.orderedDays }
            .first { $0.completedAt == nil && !$0.orderedExercises.isEmpty }
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
            .navigationTitle("Home")
        }
        .fullScreenCover(item: $openSession) { session in
            ActiveWorkoutView(day: session, profile: profile)
        }
    }

    @ViewBuilder
    private func screen(_ plan: TrainingPlan) -> some View {
        if let workout = nextWorkout {
            List {
                TodaySessionSection(session: workout, unit: profile.displayUnit)
            }
            .safeAreaInset(edge: .bottom) { action(workout) }
        } else {
            // Every session logged, or a block with nothing in it. Both read the
            // same to a lifter: there is no next workout, and the next one comes
            // from Claude.
            List {
                TodayFinishedSection(plan: plan)
            }
        }
    }

    /// Start, or pick up where the session was left. A workout with prescribed
    /// exercises always has one — `nextWorkout` never returns an empty session,
    /// so there is no button here that opens a screen with nothing on it.
    private func action(_ workout: WorkoutDay) -> some View {
        PrimaryActionButton(
            title: TodayPhrasing.actionTitle(for: TodayInPlan.progress(of: workout)),
            systemImage: "play.fill"
        ) {
            openSession = workout
        }
        .padding(Spacing.section)
        .background(.bar)
    }
}
