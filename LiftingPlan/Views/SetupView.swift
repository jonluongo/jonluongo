import SwiftUI
import SwiftData

/// Collects the three core inputs — days, duration, goal — plus equipment and
/// experience, then generates a plan. Used both for first-run onboarding and for
/// editing preferences later (as a sheet).
///
/// Training days and session length live on the generated `TrainingPlan`, not
/// on `UserProfile` — a later block can train a different split without
/// touching the profile. This view holds them as local `@State`, seeded from
/// the most recent plan (or sensible defaults when there is none yet), and
/// hands them to `PlanCoordinator` when generating.
struct SetupView: View {
    @Bindable var profile: UserProfile
    var isOnboarding: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanGenerator.self) private var generator
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    @State private var selectedWeekdays: Set<Weekday> = [.monday, .wednesday, .friday]
    @State private var durationMinutes = 45
    @State private var hasSeededSchedule = false
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private let durationOptions = [30, 45, 60, 75, 90]

    private var weekdaySelection: Binding<Set<Weekday>> {
        Binding(get: { selectedWeekdays }, set: { selectedWeekdays = $0 })
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
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
                if selectedWeekdays.isEmpty {
                    Text("Pick at least one day.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("How long per workout?") {
                Picker("Duration", selection: $durationMinutes) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("What's your goal?") {
                TextField(
                    "e.g. get stronger on bench, build my legs, tone up",
                    text: $profile.goal,
                    axis: .vertical
                )
                .lineLimit(2...4)
            }

            Section("Equipment") {
                Picker("Equipment", selection: $profile.equipmentAccess) {
                    ForEach(Equipment.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Experience") {
                Picker("Experience", selection: $profile.experience) {
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
                .disabled(selectedWeekdays.isEmpty || isGenerating)
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
        .onAppear(perform: seedScheduleIfNeeded)
        .alert("Couldn't Save", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Seed the local day/duration selection from the most recent plan the
    /// first time this view appears, so editing setup starts from what's
    /// actually scheduled rather than silently resetting it.
    private func seedScheduleIfNeeded() {
        guard !hasSeededSchedule else { return }
        hasSeededSchedule = true
        guard let latest = plans.first else { return }
        selectedWeekdays = latest.weekdays
        durationMinutes = latest.durationMinutes
    }

    private func generate() {
        guard !selectedWeekdays.isEmpty else { return }
        isGenerating = true
        profile.updatedAt = Date()
        Task {
            do {
                _ = try await PlanCoordinator.generateAndStore(
                    profile: profile,
                    weekdays: selectedWeekdays,
                    durationMinutes: durationMinutes,
                    generator: generator,
                    context: context,
                    existingPlans: plans
                )
                profile.hasCompletedSetup = true
                try context.saveOrThrow()
                isGenerating = false
                if !isOnboarding { dismiss() }
            } catch {
                isGenerating = false
                errorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
