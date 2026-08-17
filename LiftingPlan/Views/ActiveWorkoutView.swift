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

    @State private var startDate = Date()
    /// The clock being edited — an exercise's, or a group's — and the exercise
    /// being read about.
    @State private var restEditing: RestTarget?
    @State private var infoExercise: PlannedExercise?
    @State private var errorMessage: String?

    private var exercises: [PlannedExercise] { day.orderedExercises }

    /// The session in the order it is trained: an exercise, or a group of them
    /// performed as rounds. The grouping was prescribed; nothing here makes one.
    private var entries: [SessionEntry] { day.entries }

    private var totalSets: Int { exercises.reduce(0) { $0 + ($1.loggedSets ?? []).count } }
    private var completedSets: Int {
        exercises.reduce(0) { $0 + ($1.loggedSets ?? []).filter(\.isCompleted).count }
    }

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
                }

            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
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
            // there: this sheet is opened by the rest line on the card it
            // belongs to, whichever kind of card that is.
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
                onAddSet: addSet,
                onDeleteSet: delete,
                onCompletionChanged: restChanged,
                onEditRest: { restEditing = RestTarget(exercise: $0) }
            )
        } header: {
            ExerciseHeaderView(
                exercise: exercise,
                onShowInfo: { infoExercise = exercise },
                onEditRest: { restEditing = RestTarget(exercise: exercise) },
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
                onRoundChanged: restChanged,
                onEditRest: { restEditing = RestTarget(group: $0) }
            )
        } header: {
            SupersetHeaderView(
                group: group,
                onShowInfo: { infoExercise = $0 },
                onAddWarmup: { addSet(to: $0, warmup: true) }
            )
            .textCase(nil)
        }
    }

    // MARK: - Toolbar & chrome

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Its own item, and nothing beside it. Sharing one with the clock gave
        // the toolbar a single background to draw around both, so the "circle"
        // was a capsule the width of chevron-plus-gap-plus-time and the chevron
        // sat at one end of it rather than in the middle of anything.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                close()
            } label: {
                Image(systemName: "chevron.down")
            }
            .accessibilityLabel("Close workout")
        }
        // The session's running time, where the focus used to be. The focus was
        // removed as unhelpful — the lifter picked this session and is looking
        // at its exercises — and how long he has been training is the one thing
        // worth a glance that nothing else on the screen says.
        ToolbarItem(placement: .principal) {
            TimelineView(.periodic(from: startDate, by: 1)) { timeline in
                Text(elapsedString(timeline.date))
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        // There is no timer button here any more. Rest is prescribed per
        // exercise, so one control in the toolbar could not mean anything
        // specific — it opened a picker that started a stopwatch unrelated to
        // whatever set had just been logged. The rest line on each exercise's
        // card is the control now.
        // One action, and its word says which state the session is in. A
        // logged session is already recorded, so the button only closes it —
        // calling that "Finish" would ask the lifter to finish something that
        // is finished. Un-finishing is the rare correction, so it sits in the
        // menu rather than on the surface: it is what makes reopening mean
        // anything, and it is not what anyone came here to press.
        ToolbarItem(placement: .topBarTrailing) {
            if isLogged {
                Menu {
                    Button("Mark as unfinished", systemImage: "arrow.uturn.backward") {
                        day.completedAt = nil
                        _ = save()
                    }
                } label: {
                    Text("Done").fontWeight(.semibold)
                } primaryAction: {
                    close()
                }
            } else {
                Button("Finish") { finish() }
                    .fontWeight(.semibold)
            }
        }
        // A number pad has no return key, so without this the only way out of a
        // weight field is to scroll the list — which is a poor thing to require
        // of someone holding the phone in one hand between sets.
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { dismissKeyboard() }
        }
    }

    /// Resigns whatever field is first responder. The entry fields live inside
    /// `SetRowView`, several levels down and one per set, so threading a
    /// `FocusState` binding to each of them would cost more than it is worth
    /// for a button that always means the same thing.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
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

    private func close() {
        restTimer.stop()
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

    // MARK: - Helpers

    private func elapsedString(_ now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startDate)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Whose clock the rest sheet is editing: one exercise's, or one group's.
///
/// The sheet asks the same question either way — follow the plan, run this long,
/// or run nothing — so it takes one value rather than being written twice. A
/// group's choice is keyed on the exercise its round ends with, which is the
/// exercise that carries the group's rest.
private struct RestTarget: Identifiable {
    let id: String
    let name: String
    let prescribedSeconds: Int?
    let key: ExerciseID

    init(exercise: PlannedExercise) {
        id = "exercise-\(exercise.persistentModelID)"
        name = exercise.displayName
        prescribedSeconds = exercise.restSeconds
        key = exercise.exerciseID
    }

    /// `nil` for a group whose members somehow arrived without one, which the
    /// format cannot state and no screen should crash over.
    init?(group: ExerciseGroup) {
        guard let key = group.restKey else { return nil }
        id = "group-\(group.id)"
        name = group.title
        prescribedSeconds = group.restSeconds
        self.key = key
    }
}
