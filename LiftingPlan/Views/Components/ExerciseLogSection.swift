import SwiftUI
import SwiftData

/// The editable body of one exercise's section inside `ActiveWorkoutView`:
/// notes, the rest-timer picker, the set table, and "Add Set". Split out to
/// keep `ActiveWorkoutView` focused on the workout's overall flow rather than
/// per-row mechanics.
///
/// Weight is shown and entered in `profile.displayUnit`; `previousText` reads
/// the lifter's most recent performance on this exercise (keyed by
/// `exerciseID`, never by name) and converts it to that same unit.
struct ExerciseLogSection: View {
    let exercise: PlannedExercise
    let profile: UserProfile
    let plans: [TrainingPlan]
    var onAddSet: (PlannedExercise, Bool) -> Void
    var onDeleteSet: (LoggedSet, PlannedExercise) -> Void
    var onCompleteSet: (PlannedExercise) -> Void

    private let restOptions = [30, 45, 60, 75, 90, 120, 150, 180]

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

            Menu {
                ForEach(restOptions, id: \.self) { seconds in
                    Button(formatRest(seconds)) { exercise.restSeconds = seconds }
                }
            } label: {
                Label(restLabel, systemImage: "timer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            columnHeader

            ForEach(Array(orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                SetRowView(
                    set: set,
                    workingNumber: workingNumber(at: index),
                    previousText: previousText(workingIndex: workingNumber(at: index) - 1, isWarmup: set.isWarmup),
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

    /// "Rest timer: 90s", or an invitation to set one when the plan did not.
    private var restLabel: String {
        guard let seconds = exercise.restSeconds else { return "Set a rest timer" }
        return "Rest timer: \(formatRest(seconds))"
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
