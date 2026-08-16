import SwiftUI
import LiftingKit

/// Previews a day's prescribed exercises and launches the guided workout.
struct SessionDetailView: View {
    let day: WorkoutDay
    let profile: UserProfile

    @State private var showingWorkout = false

    /// "Push · 45 min", dropping either part the plan did not state.
    private var header: String {
        [day.focus, day.durationMinutes.map { "\($0) min" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// What Start actually does, which depends on whether this session was
    /// prescribed any rest. A timer runs where the plan asked for one and
    /// nowhere else — the app never decides how long to rest — so promising
    /// "automatic rest timers between every set" would be false on most
    /// sessions and would describe an app that prescribes.
    private var startFooter: String {
        let prescribesRest = day.orderedExercises.contains { $0.restSeconds != nil }
        return prescribesRest
            ? "Tap Start to log this session set by set. Where the plan prescribes rest, checking a set off runs that rest."
            : "Tap Start to log this session set by set. Nothing here prescribes rest, so no timer starts on its own — you can run one yourself from the timer button."
    }

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
                        ExercisePreviewRow(exercise: exercise, unit: profile.displayUnit)
                    }
                } header: {
                    Text(header)
                } footer: {
                    Text(startFooter)
                }
            }
        }
        .navigationTitle(day.weekday.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton(
                title: day.completedAt != nil ? "Repeat Workout" : "Start Workout",
                systemImage: "play.fill"
            ) {
                showingWorkout = true
            }
            .disabled(day.orderedExercises.isEmpty)
            .padding(Spacing.section)
            .background(.bar)
        }
        .fullScreenCover(isPresented: $showingWorkout) {
            ActiveWorkoutView(day: day, profile: profile)
        }
    }
}

/// Static preview of one prescribed exercise.
///
/// Everything shown here is the plan restated: the sets it asks for, the effort
/// it asks for, and — when its sets differ from one another — each of them on
/// its own line, since no single line can state a ramp or a drop set without
/// naming a figure no set of it actually has.
struct ExercisePreviewRow: View {
    let exercise: PlannedExercise
    /// The lifter's display unit, so a prescribed load reads in the unit he
    /// reads everything else in.
    let unit: MassUnit

    private var isComplete: Bool {
        let sets = exercise.loggedSets ?? []
        return !sets.isEmpty && sets.allSatisfy(\.isCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack {
                Text(exercise.displayName).font(.barbellTitle)
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            HStack(spacing: Spacing.standard) {
                Label(PrescriptionSummary.text(for: exercise), systemImage: "repeat")
                if let rest = exercise.restSeconds {
                    Label("\(rest)s rest", systemImage: "timer")
                }
                if let tempo = exercise.tempo {
                    Label(tempo, systemImage: "metronome")
                }
            }
            .font(.barbellSupport)
            .foregroundStyle(.secondary)

            if PrescriptionSummary.setsDiffer(in: exercise) {
                PrescriptionLines(sets: exercise.prescribedSets, unit: unit)
            }

            if let notes = exercise.notes, !notes.isEmpty {
                Text(notes)
                    .font(.barbellSupport)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.tight)
    }
}
