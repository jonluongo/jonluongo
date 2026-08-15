import SwiftUI

/// Previews a day's prescribed exercises and launches the guided workout.
struct SessionDetailView: View {
    let day: WorkoutDay
    let profile: UserProfile

    @State private var showingWorkout = false

    var body: some View {
        List {
            if day.orderedExercises.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No exercises yet", systemImage: "dumbbell")
                    } description: {
                        Text("This day has no prescribed exercises yet.")
                    }
                }
            } else {
                Section {
                    ForEach(day.orderedExercises) { exercise in
                        ExercisePreviewRow(exercise: exercise)
                    }
                } header: {
                    Text("\(day.focus) · \(day.durationMinutes) min")
                } footer: {
                    Text("Tap Start to run the session with automatic rest timers between every set.")
                }
            }
        }
        .navigationTitle(day.weekday.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingWorkout = true
            } label: {
                Label(day.completedAt != nil ? "Repeat Workout" : "Start Workout", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(day.orderedExercises.isEmpty)
            .padding()
            .background(.bar)
        }
        .fullScreenCover(isPresented: $showingWorkout) {
            ActiveWorkoutView(day: day, profile: profile)
        }
    }
}

/// Static preview of one prescribed exercise.
struct ExercisePreviewRow: View {
    let exercise: PlannedExercise

    private var isComplete: Bool {
        let sets = exercise.loggedSets ?? []
        return !sets.isEmpty && sets.allSatisfy(\.isCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(exercise.displayName).font(.headline)
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            HStack(spacing: 10) {
                Label("\(exercise.targetSets) × \(exercise.repRange)", systemImage: "repeat")
                Label("\(exercise.restSeconds)s rest", systemImage: "timer")
                if let tempo = exercise.tempo {
                    Label(tempo, systemImage: "metronome")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
