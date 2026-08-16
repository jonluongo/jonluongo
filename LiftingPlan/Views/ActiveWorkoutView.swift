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
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    @State private var startDate = Date()
    @State private var showingFinishConfirm = false
    @State private var showingRestPicker = false
    /// The last rest the lifter ran himself, kept for this session only so the
    /// sheet reopens on it. Never read from or written to the store.
    @State private var lastCustomRestSeconds = 0
    @State private var errorMessage: String?

    private var exercises: [PlannedExercise] { day.orderedExercises }

    private var totalSets: Int { exercises.reduce(0) { $0 + ($1.loggedSets ?? []).count } }
    private var completedSets: Int {
        exercises.reduce(0) { $0 + ($1.loggedSets ?? []).filter(\.isCompleted).count }
    }

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
                    ForEach(exercises) { exercise in
                        Section {
                            ExerciseLogSection(
                                exercise: exercise,
                                profile: profile,
                                plans: plans,
                                onAddSet: addSet,
                                onDeleteSet: delete,
                                onCompleteSet: startRest
                            )
                        } header: {
                            ExerciseHeaderView(exercise: exercise, onAddWarmup: { addSet(to: exercise, warmup: true) })
                                .textCase(nil)
                        }
                    }
                }

                Section {
                    Button {
                        showingFinishConfirm = true
                    } label: {
                        Text("Finish Workout")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(day.focus.isEmpty ? day.weekday.fullName : day.focus)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top) { progressBar }
            .safeAreaInset(edge: .bottom) {
                if restTimer.isRunning {
                    RestTimerBar(restTimer: restTimer)
                }
            }
            .animation(.snappy, value: restTimer.isRunning)
            .confirmationDialog("Finish this workout?", isPresented: $showingFinishConfirm, titleVisibility: .visible) {
                Button("Finish & Save") { finish() }
                Button("Keep Going", role: .cancel) {}
            }
            .alert("Couldn't Save", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingRestPicker) {
                RestDurationSheet(initialSeconds: lastCustomRestSeconds) { seconds in
                    lastCustomRestSeconds = seconds
                    restTimer.start(seconds: seconds, context: "Rest")
                }
            }
        }
        .onAppear(perform: seedSetsIfNeeded)
    }

    // MARK: - Toolbar & chrome

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 10) {
                Button {
                    close()
                } label: {
                    Image(systemName: "chevron.down")
                }
                TimelineView(.periodic(from: startDate, by: 1)) { timeline in
                    Text(elapsedString(timeline.date))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingRestPicker = true
            } label: {
                Image(systemName: "timer")
            }
            .accessibilityLabel("Rest timer")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") { showingFinishConfirm = true }
                .fontWeight(.semibold)
        }
    }

    private var progressBar: some View {
        ProgressView(value: Double(completedSets), total: Double(max(totalSets, 1)))
            .tint(.accentColor)
            .padding(.horizontal)
            .padding(.bottom, 4)
    }

    // MARK: - Actions

    /// Starts the pace timer for the rest this exercise prescribes. When none
    /// was prescribed, no timer starts — the app does not invent one. The
    /// lifter can run a timer of his own from the toolbar, which is a stopwatch
    /// for this session and does not touch what was prescribed.
    private func startRest(for exercise: PlannedExercise) {
        guard let seconds = exercise.restSeconds else { return }
        restTimer.start(seconds: seconds, context: exercise.displayName)
    }

    private func addSet(to exercise: PlannedExercise, warmup: Bool) {
        let existing = exercise.loggedSets ?? []
        let nextIndex = (existing.map(\.setIndex).max() ?? -1) + 1
        let ordered = existing.sorted { $0.setIndex < $1.setIndex }
        let template = ordered.last(where: { !$0.isWarmup })
        let set = LoggedSet(
            setIndex: nextIndex,
            load: warmup ? nil : template?.load,
            // An added working set copies the one just logged — the lifter's
            // own number, in this session. When there is none to copy it falls
            // back to the prescription, never to a rule of the app's. A hold
            // copies the hold and a carry the distance, each with no reps,
            // because those are the things a set can be and this one is the same
            // kind as the one before it.
            reps: warmup ? 0 : (template?.reps ?? RepPrescription.seededReps(for: exercise.repRange) ?? 0),
            durationSeconds: warmup
                ? nil
                : (template?.durationSeconds
                    ?? HoldPrescription.seededSeconds(for: exercise.repRange)),
            distance: warmup
                ? nil
                : (template?.distance
                    ?? WorkPrescription.seededDistance(for: exercise.repRange)),
            isWarmup: warmup
        )
        context.insert(set)
        set.exercise = exercise
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

    // MARK: - Seeding

    /// Pre-populate each exercise with exactly the sets it prescribes, primed
    /// with what the plan prescribed and nothing else.
    ///
    /// **Each row is seeded from its own set's prescription, not the
    /// exercise's average.** A ramp seeds 60, 70, 80 and a drop set seeds the
    /// lighter fourth row, because that is what was written; collapsing them
    /// into one figure would hand the lifter a session nobody prescribed. The
    /// seeded reps come from `RepPrescription`, which fills the field only when
    /// that set named one number and leaves it blank — with the prescribed
    /// target shown in its place — when it named a range. Work prescribed as a
    /// hold seeds its seconds through `HoldPrescription` instead and leaves the
    /// reps at zero, so a thirty-second plank is logged as a thirty-second hold
    /// rather than as thirty repetitions; work prescribed as a carry seeds its
    /// distance through `WorkPrescription` for the same reason. None of those
    /// numbers is ever taken from what the lifter did last time. Last session's
    /// performance is shown beside each row as reference
    /// (`ExerciseLogSection.previousText`), which is what it is for;
    /// substituting it for the prescription is how the prescription stops
    /// reaching the lifter at all. Every seeded number is editable, because
    /// what gets logged is what he actually lifts.
    private func seedSetsIfNeeded() {
        for exercise in exercises where (exercise.loggedSets ?? []).isEmpty {
            for (index, prescribed) in exercise.prescribedSets.enumerated() {
                let set = LoggedSet(
                    setIndex: index,
                    load: prescribed.suggestedLoad,
                    reps: RepPrescription.seededReps(for: prescribed.repRange) ?? 0,
                    // A hold seeds the seconds it prescribes and a carry the
                    // distance, each leaving the reps at zero. Only one of the
                    // three is ever filled in, because a set is counted, held,
                    // or carried, and never two of them at once.
                    durationSeconds: HoldPrescription.seededSeconds(for: prescribed.repRange),
                    distance: WorkPrescription.seededDistance(for: prescribed.repRange),
                    isWarmup: false
                )
                context.insert(set)
                set.exercise = exercise
            }
        }
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

/// Section header for an exercise: icon, name, and an overflow menu.
private struct ExerciseHeaderView: View {
    let exercise: PlannedExercise
    var onAddWarmup: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "dumbbell.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                // What the plan prescribed, stated the way it was written: a
                // count and a rep target when the sets are alike, and only the
                // count when they are not — the set rows below say the rest.
                Text("\(PrescriptionSummary.text(for: exercise))\(exercise.tempo.map { " · tempo \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { onAddWarmup() } label: {
                    Label("Add Warmup Set", systemImage: "flame")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.vertical, 4)
    }
}
