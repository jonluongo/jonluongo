import SwiftUI
import SwiftData

/// The editable body of one exercise's section inside `ActiveWorkoutView`:
/// notes, the prescribed rest, the set table, and "Add Set". Split out to keep
/// `ActiveWorkoutView` focused on the workout's overall flow rather than
/// per-row mechanics.
///
/// Weight is shown and entered in `profile.displayUnit`; `previousText` reads
/// the lifter's most recent performance on this exercise (keyed by
/// `exerciseID`, never by name) and converts it to that same unit.
///
/// **The only thing this section writes is the log.** The prescription — sets,
/// reps, rest — is read and displayed, never edited: a rest the lifter changed
/// in the gym would go out in the snapshot as though Claude had prescribed it,
/// and he would read his own plan back with a number he never wrote. Running a
/// timer of one's own is a session-local stopwatch and lives in
/// `ActiveWorkoutView`'s toolbar instead.
struct ExerciseLogSection: View {
    let exercise: PlannedExercise
    let profile: UserProfile
    let plans: [TrainingPlan]
    var onAddSet: (PlannedExercise, Bool) -> Void
    var onDeleteSet: (LoggedSet, PlannedExercise) -> Void
    var onCompleteSet: (PlannedExercise) -> Void

    private var orderedSets: [LoggedSet] {
        (exercise.loggedSets ?? []).sorted { $0.setIndex < $1.setIndex }
    }

    var body: some View {
        Group {
            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Shown only when the plan prescribed a rest. Nothing is drawn when
            // it did not, and nothing invites the lifter to fill the gap in.
            if let restLabel = RestPrescription.label(seconds: exercise.restSeconds) {
                Label(restLabel, systemImage: "timer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            columnHeader

            ForEach(Array(orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                SetRowView(
                    set: set,
                    workingNumber: workingNumber(at: index),
                    previousText: previousText(workingIndex: workingNumber(at: index) - 1, isWarmup: set.isWarmup),
                    repTargetText: RepPrescription.targetText(for: exercise.repRange),
                    unit: profile.displayUnit,
                    onComplete: { onCompleteSet(exercise) }
                )
                .listRowBackground(set.isCompleted ? Color.green.opacity(0.12) : nil)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onDeleteSet(set, exercise) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Button {
                onAddSet(exercise, false)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: 30)
            Text("PREVIOUS").frame(maxWidth: .infinity)
            Text(profile.displayUnit.rawValue.uppercased()).frame(width: 62)
            Text("REPS").frame(width: 62)
            Image(systemName: "checkmark").frame(width: 30)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// 1-based working-set number for the row at `index` (warmups don't count).
    private func workingNumber(at index: Int) -> Int {
        orderedSets.prefix(index + 1).filter { !$0.isWarmup }.count
    }

    private func previousText(workingIndex: Int, isWarmup: Bool) -> String {
        guard !isWarmup, workingIndex >= 0 else { return "—" }
        let previous = PerformanceHistory.latestHistory(
            for: exercise.exerciseID, excluding: exercise, from: plans
        )?.recentSets ?? []
        guard workingIndex < previous.count else { return "—" }
        let record = previous[workingIndex]
        if let load = record.load?.converted(to: profile.displayUnit), load.value > 0 {
            return "\(load.value.compactString) × \(record.reps)"
        }
        return "\(record.reps) reps"
    }
}
