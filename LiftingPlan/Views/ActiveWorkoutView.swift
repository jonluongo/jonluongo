import SwiftUI
import SwiftData

/// The guided workout: one exercise at a time, log each set, and an automatic
/// rest/pace timer fires the moment a set is logged to keep tempo up.
struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimerModel.self) private var restTimer
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

    @State private var currentIndex = 0
    @State private var weightText = ""
    @State private var reps = 10
    @State private var rpe: Double? = nil
    @State private var showingFinishConfirm = false

    private var exercises: [PlannedExercise] { session.orderedExercises }
    private var currentExercise: PlannedExercise? {
        guard exercises.indices.contains(currentIndex) else { return nil }
        return exercises[currentIndex]
    }

    var body: some View {
        NavigationStack {
            Group {
                if let exercise = currentExercise {
                    workoutBody(for: exercise)
                } else {
                    ContentUnavailableView("No exercises", systemImage: "dumbbell")
                }
            }
            .navigationTitle(session.focus)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Finish") { showingFinishConfirm = true }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Finish this workout?", isPresented: $showingFinishConfirm, titleVisibility: .visible) {
                Button("Finish & Save") { finish() }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("Your logged sets are saved either way.")
            }
        }
        .onAppear { primeInputs(for: currentExercise) }
        .onChange(of: currentIndex) { _, _ in
            restTimer.stop()
            primeInputs(for: currentExercise)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func workoutBody(for exercise: PlannedExercise) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                exerciseHeader(exercise)

                if restTimer.isRunning || restTimer.remaining > 0 {
                    restTimerCard
                }

                loggedSetsCard(exercise)
                setEntryCard(exercise)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { navigationBar }
        .background(Color(.systemGroupedBackground))
    }

    private func exerciseHeader(_ exercise: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercise \(currentIndex + 1) of \(exercises.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(exercise.name)
                .font(.title2.bold())

            HStack(spacing: 10) {
                metric("SETS", "\(loggedCount(exercise))/\(exercise.targetSets)")
                metric("REPS", exercise.repRange)
                metric("REST", "\(exercise.restSeconds)s")
                if let tempo = exercise.tempo { metric("TEMPO", tempo) }
            }

            if let suggestion = progressionSuggestion(for: exercise) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: suggestion.isPush ? "arrow.up.forward.circle.fill" : "equal.circle.fill")
                        .foregroundStyle(suggestion.isPush ? .orange : .secondary)
                    Text(suggestion.rationale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
            }

            if let notes = exercise.notes, !notes.isEmpty {
                Label(notes, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rest timer

    private var restTimerCard: some View {
        VStack(spacing: 14) {
            TimerRing(
                progress: restTimer.progress,
                timeText: restTimer.formattedRemaining,
                isRunning: restTimer.isRunning
            )
            HStack(spacing: 12) {
                Button {
                    restTimer.addTime(30)
                } label: {
                    Label("30s", systemImage: "goforward.30").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    restTimer.skip()
                } label: {
                    Label("Skip", systemImage: "forward.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Logged sets

    private func loggedSetsCard(_ exercise: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Logged sets").font(.headline)
            if exercise.setLogs.isEmpty {
                Text("No sets yet — log your first set below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(exercise.orderedSetLogs) { set in
                    HStack {
                        Text("Set \(set.setIndex + 1)").foregroundStyle(.secondary)
                        Spacer()
                        Text(setSummary(set))
                            .fontWeight(.medium)
                            .monospacedDigit()
                        Button(role: .destructive) {
                            delete(set, from: exercise)
                        } label: {
                            Image(systemName: "trash").font(.footnote)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Set entry

    private func setEntryCard(_ exercise: PlannedExercise) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEIGHT (lb)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("REPS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Stepper(value: $reps, in: 0...100) {
                        Text("\(reps)").font(.title3.monospacedDigit())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("EFFORT (RPE) — optional").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Picker("RPE", selection: Binding(get: { rpe ?? 0 }, set: { rpe = $0 == 0 ? nil : $0 })) {
                    Text("—").tag(0.0)
                    ForEach([6.0, 7.0, 8.0, 9.0, 10.0], id: \.self) { value in
                        Text(String(Int(value))).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button(action: { logSet(for: exercise) }) {
                Label("Log Set & Start Rest", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            Button {
                if currentIndex > 0 { currentIndex -= 1 }
            } label: {
                Label("Prev", systemImage: "chevron.left").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(currentIndex == 0)

            if currentIndex < exercises.count - 1 {
                Button {
                    currentIndex += 1
                } label: {
                    Label("Next", systemImage: "chevron.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    showingFinishConfirm = true
                } label: {
                    Label("Finish", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Actions

    private func logSet(for exercise: PlannedExercise) {
        let weight = Double(weightText.replacingOccurrences(of: ",", with: "."))
        let set = SetLog(
            setIndex: exercise.setLogs.count,
            weight: (weight ?? 0) > 0 ? weight : nil,
            reps: reps,
            rpe: rpe
        )
        context.insert(set)
        // Setting the inverse relationship links it into `exercise.setLogs`;
        // don't also append manually or the set would be listed twice.
        set.exercise = exercise
        try? context.save()

        restTimer.start(
            seconds: exercise.restSeconds,
            context: "\(exercise.name) — set \(exercise.setLogs.count + 1)"
        )
    }

    private func delete(_ set: SetLog, from exercise: PlannedExercise) {
        exercise.setLogs.removeAll { $0 === set }
        context.delete(set)
        // Re-index remaining sets so labels stay 1..n.
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

    // MARK: - Helpers

    private func loggedCount(_ exercise: PlannedExercise) -> Int { exercise.setLogs.count }

    private func setSummary(_ set: SetLog) -> String {
        var parts: [String] = []
        if let weight = set.weight {
            parts.append("\(ProgressionEngine.formatted(weight)) lb × \(set.reps)")
        } else {
            parts.append("\(set.reps) reps")
        }
        if let rpe = set.rpe {
            parts.append("@\(ProgressionEngine.formatted(rpe))")
        }
        return parts.joined(separator: "  ")
    }

    private func progressionSuggestion(for exercise: PlannedExercise) -> ProgressionSuggestion? {
        guard let history = PerformanceHistory.latestHistory(
            forExerciseNamed: exercise.name,
            excluding: exercise,
            from: plans
        ) else { return nil }
        return ProgressionEngine.suggestion(for: history)
    }

    private func primeInputs(for exercise: PlannedExercise?) {
        guard let exercise else { return }
        reps = max(exercise.repTargetUpperBound, 1)
        rpe = nil
        // Prefer a progression-based target, then any suggested weight, else blank.
        if let suggestion = progressionSuggestion(for: exercise), let weight = suggestion.suggestedWeight {
            weightText = ProgressionEngine.formatted(weight)
        } else if let suggested = exercise.suggestedWeight {
            weightText = ProgressionEngine.formatted(suggested)
        } else {
            weightText = ""
        }
    }
}
