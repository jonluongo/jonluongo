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
        NavigationStack {
            List {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises", systemImage: "dumbbell")
                    } description: {
                        Text("This day has no prescribed exercises to log.")
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
                        isLogged: isLogged, onFinish: finish, onUnfinish: unfinish)
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
            // The session's own name, large at the top of the scroll and
            // collapsing into the bar as it moves — the platform's own
            // behaviour, and what fills a band that previously held a clock, a
            // close button, and a hundred points of nothing.
            .navigationTitle(
                TodayPhrasing.sessionTitle(focus: day.focus, weekday: day.weekday))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ActiveWorkoutToolbar(
                    startedAt: day.startedAt, finishedAt: day.completedAt, onClose: close)
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
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { infoExercise = nil }.fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .onAppear(perform: seedSetsIfNeeded)
    }

    // MARK: - One card per entry

    /// An exercise performed on its own — exactly the card it has always been.
    @ViewBuilder
    private func section(for exercise: PlannedExercise) -> some View {
        Section {
            ExerciseLogSection(
                exercise: exercise,
                profile: profile,
                plans: plans,
                onDeleteSet: delete,
                onCompletionChanged: restChanged
            )
        } header: {
            ExerciseHeaderView(
                exercise: exercise,
                unit: profile.displayUnit,
                onShowInfo: { infoExercise = exercise },
                onEditRest: { restEditing = RestTarget(exercise: exercise) },
                onAddSet: { addSet(to: exercise, warmup: false) },
                onAddWarmup: { addSet(to: exercise, warmup: true) }
            )
            .textCase(nil)
        }
    }

    /// A group, as one card: the card is the group because the group is the unit
    /// of work.
    @ViewBuilder
    private func section(for group: ExerciseGroup) -> some View {
        Section {
            SupersetLogSection(
                group: group,
                profile: profile,
                plans: plans,
                onAddRound: addRound,
                onDeleteSet: delete,
                onRoundChanged: restChanged
            )
        } header: {
            SupersetHeaderView(
                group: group,
                unit: profile.displayUnit,
                onShowInfo: { infoExercise = $0 },
                onAddWarmup: { addSet(to: $0, warmup: true) },
                onEditRest: { restEditing = RestTarget(group: $0) }
            )
            .textCase(nil)
        }
    }

    // MARK: - Actions

    /// Runs the rest this exercise asks for when a set is ticked, and stops it
    /// when one is taken back.
    ///
    /// Unchecking used to leave the timer running, which made the bar outlast
    /// the thing it was counting for. A set taken back did not happen, so there
    /// is nothing to be resting from.
    ///
    /// **How long it runs is the lifter's to say and Claude's to prescribe, in
    /// that order.** `RestPreferences` answers with the prescribed rest until
    /// the lifter says otherwise, with his own length once he has, and with
    /// nothing when he has switched the clock off here or everywhere. When the
    /// plan prescribed no rest and he has asked for none, no timer starts — the
    /// app does not invent one.
    private func restChanged(for exercise: PlannedExercise, isCompleted: Bool) {
        guard isCompleted else {
            restTimer.stop()
            return
        }
        guard let seconds = restPreferences.runningSeconds(
            prescribed: exercise.restSeconds, for: exercise.exerciseID
        ) else { return }
        restTimer.start(seconds: seconds, context: exercise.displayName)
    }

    /// Runs the group's rest when a *round* finishes, and stops it when a set of
    /// a finished round is taken back.
    ///
    /// This is the one behavioural difference a group makes, and the reason the
    /// grouping is worth expressing: resting only after the group is what a
    /// superset is. Ticking A1 starts nothing, because the next movement of the
    /// round follows immediately.
    ///
    /// How long it runs is the lifter's to say and Claude's to prescribe, in
    /// that order — the same rule an exercise on its own follows, asked of the
    /// exercise the round ends with, which is the one that carries the rest.
    private func restChanged(for group: ExerciseGroup, roundCompleted: Bool) {
        guard roundCompleted else {
            restTimer.stop()
            return
        }
        guard let key = group.restKey,
            let seconds = restPreferences.runningSeconds(
                prescribed: group.restSeconds, for: key)
        else { return }
        restTimer.start(seconds: seconds, context: group.title)
    }

    private func addSet(to exercise: PlannedExercise, warmup: Bool) {
        SetSeeding.addSet(to: exercise, warmup: warmup, in: context)
        save()
    }

    /// One more round: one row on every movement of the group, because a round
    /// is one set of each and half a round is not a round.
    private func addRound(to group: ExerciseGroup) {
        for member in group.members {
            SetSeeding.addSet(to: member, warmup: false, in: context)
        }
        save()
    }

    private func delete(_ set: LoggedSet, from exercise: PlannedExercise) {
        exercise.loggedSets?.removeAll { $0 === set }
        context.delete(set)
        let remaining = (exercise.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }
        for (index, set) in remaining.enumerated() {
            set.setIndex = index
        }
        save()
    }

    private func finish() {
        restTimer.stop()
        if day.completedAt == nil {
            day.completedAt = Date()
        }
        guard save() else { return }
        dismiss()
    }

    /// Takes a finished session back to unfinished, which is what makes
    /// reopening one mean anything.
    private func unfinish() {
        day.completedAt = nil
        save()
    }

    /// Leaves the session. It does **not** stop the rest timer.
    ///
    /// It used to, which meant closing the screen mid-rest threw the rest away
    /// — and closing the screen is exactly what a lifter does with ninety
    /// seconds to wait. The timer is date-based and lives above this screen, so
    /// it keeps counting while he is elsewhere and the cue still reaches a
    /// pocketed phone. Finishing stops it, because then there is nothing left
    /// to be resting for.
    private func close() {
        guard save() else { return }
        dismiss()
    }

    /// Fills the table in from the prescription the first time this session is
    /// opened. The rule for what each row starts as lives in `SetSeeding`; what
    /// belongs here is the save, and showing the lifter when it fails.
    private func seedSetsIfNeeded() {
        SetSeeding.seedMissingSets(for: exercises, in: context)
        save()
    }

    // MARK: - Saving

    /// Persists pending changes, surfacing any failure via `errorMessage`
    /// rather than discarding it. Returns whether the save succeeded, so
    /// callers that should only proceed on success (`finish`, `close`) can
    /// bail out and leave the sheet open for the lifter to retry.
    @discardableResult
    private func save() -> Bool {
        do {
            try context.saveOrThrow()
            return true
        } catch {
            errorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
