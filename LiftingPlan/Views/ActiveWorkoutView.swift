import SwiftUI
import SwiftData
import LiftingKit

/// The guided workout, spreadsheet-style: every exercise in one scroll, each with
/// an editable table of sets (set · previous · weight · reps · ✓). Checking a set
/// off starts the rest/pace timer, which floats in a bar at the bottom.
struct ActiveWorkoutView: View {
    let day: WorkoutDay
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimerModel.self) private var restTimer
    /// The lifter's own clock: whether it runs at all, and how long on each
    /// exercise. Not the prescription, and not in the store.
    @Environment(RestPreferences.self) private var restPreferences
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// The clock being edited — an exercise's, or a group's — and the exercise
    /// being read about.
    @State private var restEditing: RestTarget?
    @State private var infoExercise: PlannedExercise?
    @State private var errorMessage: String?

    private var exercises: [PlannedExercise] { day.orderedExercises }

    /// The session in the order it is trained: an exercise, or a group of them
    /// performed as rounds. The grouping was prescribed; nothing here makes one.
    private var entries: [SessionEntry] { day.entries }

    /// Whether this session has been marked done. Not derived from how much of
    /// it is filled in: a lifter who stops at three sets of four has finished,
    /// and one resting between sets has not, and nothing in the record can tell
    /// those apart. Only he can, which is what the button is for.
    private var isLogged: Bool { day.completedAt != nil }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
            List {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises", systemImage: "dumbbell")
                    }
                } else {
                    ForEach(entries) { entry in
                        switch entry {
                        case .exercise(let exercise): section(for: exercise)
                        case .group(let group): section(for: group)
                        }
                    }
                    // Past the last set, which is where a lifter who has
                    // finished arrives. It used to be top right, where it was
                    // pressed as a way out of the screen.
                    SessionFinishSection(
                        isLogged: isLogged, unloggedSetCount: day.unloggedSetCount,
                        onFinish: { write(log.finish) }, onUnfinish: { write(log.unfinish) })
                }

            }
            // Plain, with the panel drawn by the rows themselves — see
            // `panelRow`. Inset-grouped would draw its own panel underneath, at
            // its own corner radius, and the radius is the point: the system's
            // is drawn for cards of content and these hold a table of figures.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .scrollDismissesKeyboard(.interactively)
            // No title. It was the session's name, large, filling the band this
            // screen used to waste — but the name is on the card the lifter
            // came from and on every screen that led here, and a heading over a
            // session he is already inside answers a question nobody has. An
            // inline bar with nothing in the middle collapses to its own height,
            // which is tighter than the large title was and tighter than the
            // empty band before it.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ActiveWorkoutToolbar()
                // The way out, back where it belongs. Top right means dismiss
                // and only dismiss now: Finish lives under the last set, so the
                // corner that once marked an untouched session as trained can
                // safely hold the thing everyone reads it as.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close workout")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if restTimer.isRunning {
                    RestTimerBar(restTimer: restTimer)
                }
            }
            .animation(.snappy, value: restTimer.isRunning)
            .alert("Couldn't Save", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            // Rest is prescribed per exercise and per group, so it is edited
            // per exercise and per group: this sheet is opened from the menu on
            // the card it belongs to, whichever kind of card that is.
            .sheet(item: $restEditing) { target in
                ExerciseRestSheet(
                    exerciseName: target.name,
                    prescribedSeconds: target.prescribedSeconds,
                    timersEnabled: restPreferences.timersEnabled,
                    rest: restPreferences.rest(for: target.key)
                ) { rest in
                    restPreferences.setRest(rest, for: target.key)
                }
            }
            // The same screen the exercise row pushes elsewhere in the app —
            // what the movement is and what has been lifted on it are one
            // exercise, and were never worth two destinations.
            .sheet(item: $infoExercise) { exercise in
                NavigationStack {
                    ExerciseDetailView(
                        exerciseID: exercise.exerciseID,
                        displayName: exercise.displayName,
                        unit: profile.displayUnit
                    )
                }
                // The grabber, as on the block and account sheets. This one had
                // a Done button, so the app dismissed two of its sheets by
                // swipe and one by tap — three sheets, two vocabularies. The
                // platform does the dismissing either way; the button was chrome
                // for a behaviour that already exists.
                .presentationDragIndicator(.visible)
            }
        .onAppear { write(log.seedIfNeeded) }
    }

    // MARK: - One card per entry

    /// An exercise performed on its own — exactly the card it has always been.
    @ViewBuilder
    private func section(for exercise: PlannedExercise) -> some View {
        // The name sits on the panel rather than above it, so an exercise is
        // one object — its title, its prescription and its sets — instead of a
        // label floating over a table that happens to be beneath it.
        Section {
            ExerciseHeaderView(
                exercise: exercise,
                unit: profile.displayUnit,
                onShowInfo: { infoExercise = exercise },
                onEditRest: { restEditing = RestTarget(exercise: exercise) },
                onAddSet: { write { try log.addSet(to: exercise, warmup: false) } },
                onAddWarmup: { write { try log.addSet(to: exercise, warmup: true) } }
            )
            .panelRow(.first)
            .listRowSeparator(.hidden)

            ExerciseLogSection(
                exercise: exercise,
                profile: profile,
                plans: plans,
                onDeleteSet: { set, exercise in
                    write { try log.delete(set, from: exercise) }
                },
                onCompletionChanged: { exercise, completed in
                    write { try log.completionChanged(for: exercise, isCompleted: completed) }
                }
            )
        }
    }

    /// A group, as one card: the card is the group because the group is the unit
    /// of work.
    @ViewBuilder
    private func section(for group: ExerciseGroup) -> some View {
        // A group is drawn as its movements are drawn — each with the header and
        // the set table an ungrouped exercise gets — sharing one panel with no
        // gap between them. Every other exercise on the screen keeps a gap from
        // its neighbour, so two that do not are visibly one thing. That is the
        // whole of the notation: no "Superset A", no A1/A2, no legend decoding
        // symbols the layout had invented, and no round labels restating a set
        // number. Rest still runs when the round closes, which is what a
        // superset actually is.
        Section {
            ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                ExerciseHeaderView(
                    exercise: member,
                    unit: profile.displayUnit,
                    onShowInfo: { infoExercise = member },
                    onEditRest: { restEditing = RestTarget(group: group) },
                    onAddSet: { write { try log.addSet(to: member, warmup: false) } },
                    onAddWarmup: { write { try log.addSet(to: member, warmup: true) } },
                    paired: true
                )
                .panelRow(.first, paired: true)
                .listRowSeparator(.hidden)

                ExerciseLogSection(
                    exercise: member,
                    profile: profile,
                    plans: plans,
                    onDeleteSet: { set, exercise in
                        write { try log.delete(set, from: exercise) }
                    },
                    onCompletionChanged: { _, completed in
                        write { try log.roundCompletionChanged(group, completed: completed) }
                    },
                    paired: true
                )
            }
        }
    }

    // MARK: - Doing

    /// Everything this screen does rather than draws. Built per redraw from what
    /// the view already holds, so there is no second copy of the session's state
    /// to keep in step with the first.
    private var log: SessionLog {
        SessionLog(
            day: day, context: context, restTimer: restTimer,
            restPreferences: restPreferences, plans: plans, unit: profile.displayUnit)
    }

    /// Runs a write and shows the lifter when it fails, rather than discarding
    /// the error. With CloudKit sync a save conflict is expected, not
    /// exceptional.
    private func write(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = (error as? PersistenceError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
