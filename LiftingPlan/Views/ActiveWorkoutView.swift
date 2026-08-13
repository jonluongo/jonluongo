import SwiftUI
import SwiftData

/// The guided workout, spreadsheet-style: every exercise in one scroll, each with
/// an editable table of sets (set · previous · lbs · reps · ✓). Checking a set off
/// starts the rest/pace timer, which floats in a bar at the bottom.
struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimerModel.self) private var restTimer
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

    @State private var startDate = Date()
    @State private var showingFinishConfirm = false

    private let restOptions = [30, 45, 60, 75, 90, 120, 150, 180]

    private var exercises: [PlannedExercise] { session.orderedExercises }

    private var totalSets: Int { exercises.reduce(0) { $0 + $1.setLogs.count } }
    private var completedSets: Int {
        exercises.reduce(0) { $0 + $1.setLogs.filter(\.isCompleted).count }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises) { exercise in
                    Section {
                        exerciseRows(exercise)
                    } header: {
                        ExerciseHeaderView(exercise: exercise, onAddWarmup: { addSet(to: exercise, warmup: true) })
                            .textCase(nil)
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
            .navigationTitle(session.focus)
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

    // MARK: - Exercise rows

    @ViewBuilder
    private func exerciseRows(_ exercise: PlannedExercise) -> some View {
        if let notes = exercise.notes, !notes.isEmpty {
            Text(notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Menu {
            ForEach(restOptions, id: \.self) { seconds in
                Button(formatRest(seconds)) { exercise.restSeconds = seconds }
            }
        } label: {
            Label("Rest timer: \(formatRest(exercise.restSeconds))", systemImage: "timer")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }

        columnHeader

        let ordered = exercise.orderedSetLogs
        ForEach(Array(ordered.enumerated()), id: \.element.persistentModelID) { index, set in
            SetRowView(
                set: set,
                workingNumber: workingNumber(at: index, in: ordered),
                previousText: previousText(for: exercise, workingIndex: workingNumber(at: index, in: ordered) - 1, isWarmup: set.isWarmup),
                onComplete: { startRest(for: exercise) }
            )
            .listRowBackground(set.isCompleted ? Color.green.opacity(0.12) : nil)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { delete(set, from: exercise) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }

        Button {
            addSet(to: exercise, warmup: false)
        } label: {
            Label("Add Set", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: 30)
            Text("PREVIOUS").frame(maxWidth: .infinity)
            Text("LBS").frame(width: 62)
            Text("REPS").frame(width: 62)
            Image(systemName: "checkmark").frame(width: 30)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func startRest(for exercise: PlannedExercise) {
        restTimer.start(seconds: exercise.restSeconds, context: exercise.name)
    }

    private func addSet(to exercise: PlannedExercise, warmup: Bool) {
        let nextIndex = (exercise.setLogs.map(\.setIndex).max() ?? -1) + 1
        let template = exercise.orderedSetLogs.last(where: { !$0.isWarmup })
        let set = SetLog(
            setIndex: nextIndex,
            weight: warmup ? nil : template?.weight,
            reps: warmup ? 0 : (template?.reps ?? exercise.repTargetUpperBound),
            isWarmup: warmup
        )
        context.insert(set)
        set.exercise = exercise
        try? context.save()
    }

    private func delete(_ set: SetLog, from exercise: PlannedExercise) {
        exercise.setLogs.removeAll { $0 === set }
        context.delete(set)
        for (index, remaining) in exercise.orderedSetLogs.enumerated() {
            remaining.setIndex = index
        }
        try? context.save()
    }

    private func finish() {
        restTimer.stop()
        if session.completedAt == nil {
            session.completedAt = Date()
        }
        try? context.save()
        dismiss()
    }

    private func close() {
        restTimer.stop()
        try? context.save()
        dismiss()
    }

    // MARK: - Seeding

    /// Pre-populate each exercise with its prescribed number of empty working
    /// sets, primed with the progression target and last time's reps.
    private func seedSetsIfNeeded() {
        for exercise in exercises where exercise.setLogs.isEmpty {
            let previous = previousRecords(for: exercise)
            let seededWeight = seedWeight(for: exercise)
            for index in 0..<max(exercise.targetSets, 1) {
                let priorReps = index < previous.count ? previous[index].reps : exercise.repTargetUpperBound
                let set = SetLog(
                    setIndex: index,
                    weight: seededWeight,
                    reps: priorReps,
                    isWarmup: false
                )
                context.insert(set)
                set.exercise = exercise
            }
        }
        try? context.save()
    }

    private func seedWeight(for exercise: PlannedExercise) -> Double? {
        if let history = PerformanceHistory.latestHistory(forExerciseNamed: exercise.name, excluding: exercise, from: plans),
           let suggested = ProgressionEngine.suggestion(for: history).suggestedWeight {
            return suggested
        }
        return exercise.suggestedWeight
    }

    // MARK: - Previous column

    private func previousRecords(for exercise: PlannedExercise) -> [SetRecord] {
        PerformanceHistory.latestHistory(forExerciseNamed: exercise.name, excluding: exercise, from: plans)?.recentSets ?? []
    }

    private func previousText(for exercise: PlannedExercise, workingIndex: Int, isWarmup: Bool) -> String {
        guard !isWarmup, workingIndex >= 0 else { return "—" }
        let previous = previousRecords(for: exercise)
        guard workingIndex < previous.count else { return "—" }
        let record = previous[workingIndex]
        if let weight = record.weight, weight > 0 {
            return "\(ProgressionEngine.formatted(weight)) × \(record.reps)"
        }
        return "\(record.reps) reps"
    }

    // MARK: - Helpers

    /// 1-based working-set number for the row at `index` (warmups don't count).
    private func workingNumber(at index: Int, in ordered: [SetLog]) -> Int {
        ordered.prefix(index + 1).filter { !$0.isWarmup }.count
    }

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
                Text(exercise.name)
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
