import SwiftUI

/// Previews a day's prescribed exercises and launches the guided workout.
struct SessionDetailView: View {
    let session: WorkoutSession

    @State private var showingWorkout = false

    var body: some View {
        List {
            Section {
                ForEach(session.orderedExercises) { exercise in
                    ExercisePreviewRow(exercise: exercise)
                }
            } header: {
                Text("\(session.focus) · \(session.targetDurationMinutes) min")
            } footer: {
                Text("Tap Start to run the session with automatic rest timers between every set.")
            }
        }
        .navigationTitle(session.weekday.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingWorkout = true
            } label: {
                Label(session.isCompleted ? "Repeat Workout" : "Start Workout", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
        .fullScreenCover(isPresented: $showingWorkout) {
            ActiveWorkoutView(session: session)
        }
    }
}

/// Static preview of one prescribed exercise.
struct ExercisePreviewRow: View {
    let exercise: PlannedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(exercise.name).font(.headline)
                Spacer()
                if exercise.isComplete {
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
