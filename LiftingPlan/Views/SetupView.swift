import SwiftUI
import SwiftData

/// Collects the three core inputs — days, duration, goal — plus equipment and
/// experience, then generates a plan. Used both for first-run onboarding and for
/// editing preferences later (as a sheet).
struct SetupView: View {
    @Bindable var preferences: TrainingPreferences
    var isOnboarding: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanGenerator.self) private var generator
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

    @State private var isGenerating = false

    private let durationOptions = [30, 45, 60, 75, 90]

    private var weekdaySelection: Binding<Set<Weekday>> {
        Binding(get: { preferences.weekdays }, set: { preferences.weekdays = $0 })
    }

    var body: some View {
        Form {
            if isOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Let's build your week")
                            .font(.title2.bold())
                        Text("Tell me when you train and what you're chasing. I'll turn your casual sessions into a plan that pushes you.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Which days do you want to train?") {
                WeekdayChips(selection: weekdaySelection)
                    .padding(.vertical, 4)
                if preferences.weekdays.isEmpty {
                    Text("Pick at least one day.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("How long per workout?") {
                Picker("Duration", selection: $preferences.durationMinutes) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("What's your goal?") {
                TextField(
                    "e.g. get stronger on bench, build my legs, tone up",
                    text: $preferences.goal,
                    axis: .vertical
                )
                .lineLimit(2...4)
            }

            Section("Equipment") {
                Picker("Equipment", selection: $preferences.equipment) {
                    ForEach(Equipment.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Experience") {
                Picker("Experience", selection: $preferences.experience) {
                    ForEach(ExperienceLevel.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button(action: generate) {
                    HStack {
                        Spacer()
                        if isGenerating {
                            ProgressView().tint(.white)
                            Text("Building your plan…")
                        } else {
                            Image(systemName: "sparkles")
                            Text(isOnboarding ? "Generate My Plan" : "Save & Regenerate Plan")
                        }
                        Spacer()
                    }
                    .fontWeight(.semibold)
                }
                .disabled(preferences.weekdays.isEmpty || isGenerating)
            } footer: {
                Text(generator.availability.statusMessage)
            }
        }
        .navigationTitle(isOnboarding ? "Welcome" : "Edit Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isOnboarding {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isGenerating)
    }

    private func generate() {
        guard !preferences.weekdays.isEmpty else { return }
        isGenerating = true
        preferences.updatedAt = Date()
        Task {
            await PlanCoordinator.generateAndStore(
                preferences: preferences,
                generator: generator,
                context: context,
                existingPlans: plans
            )
            preferences.hasCompletedSetup = true
            try? context.save()
            isGenerating = false
            if !isOnboarding { dismiss() }
        }
    }
}
