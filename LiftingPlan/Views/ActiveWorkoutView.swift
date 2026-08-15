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
    @State private var errorMessage: String?

    private let restOptions = [30, 45, 60, 75, 90, 120, 150, 180]

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
            Menu {
                ForEach(restOptions, id: \.self) { seconds in
                    Button(formatRest(seconds)) {
                        restTimer.start(seconds: seconds, context: "Rest")
                    }
                }
            } label: {
                Image(systemName: "timer")
            }
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
    /// lifter can set a rest himself from the log, which starts it from then on.
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
            reps: warmup ? 0 : (template?.reps ?? RepRange(exercise.repRange).upperBound),
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
    /// with the load it prescribes and last time's reps.
    ///
    /// The seeded load is `exercise.suggestedLoad` and nothing else. What the
    /// lifter did last time is shown beside each row as reference — see
    /// `previousRecords(for:)` — but it is never substituted for the
    /// prescription. Every seeded number is editable; the lifter logs what he
    /// actually lifts.
    private func seedSetsIfNeeded() {
        for exercise in exercises where (exercise.loggedSets ?? []).isEmpty {
            let previous = previousRecords(for: exercise)
            let repTargetUpper = RepRange(exercise.repRange).upperBound
            for index in 0..<exercise.targetSets {
                let priorReps = index < previous.count ? previous[index].reps : repTargetUpper
                let set = LoggedSet(
                    setIndex: index,
                    load: exercise.suggestedLoad,
                    reps: priorReps,
                    isWarmup: false
                )
                context.insert(set)
                set.exercise = exercise
            }
        }
        save()
    }

    // MARK: - Previous column

    private func previousRecords(for exercise: PlannedExercise) -> [SetRecord] {
        PerformanceHistory.latestHistory(for: exercise.exerciseID, excluding: exercise, from: plans)?.recentSets ?? []
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

    private func formatRest(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return remainder == 0 ? "\(minutes)min" : "\(minutes)min \(remainder)s"
        }
        return "\(seconds)s"
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
                Text("\(exercise.targetSets) × \(exercise.repRange)\(exercise.tempo.map { " · tempo \($0)" } ?? "")")
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
