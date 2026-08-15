import SwiftUI
import SwiftData

/// Collects the standing facts about the lifter — training days, session
/// length, goal, equipment, experience — and saves them to his `UserProfile`.
/// Used both for first-run onboarding and for editing preferences later (as a
/// sheet).
///
/// Saving is what completes setup; there is nothing else to wait for. The
/// view collects, it does not conclude: nothing here decides what the lifter
/// should train, only what he told us about himself.
///
/// Depends on: `UserProfile` from Store and `Weekday` from Domain.
struct SetupView: View {
    @Bindable var profile: UserProfile
    var isOnboarding: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanGenerator.self) private var generator
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    @State private var selectedWeekdays: Set<Weekday> = []
    @State private var durationMinutes: Int?
    @State private var hasSeededSchedule = false
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private let durationOptions = [30, 45, 60, 75, 90]

    /// Setup is answerable only once the lifter has said when and how long.
    private var canSave: Bool { !selectedWeekdays.isEmpty && durationMinutes != nil }

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
                        Text("\(minutes) min").tag(Int?.some(minutes))
                    }
                }
                .pickerStyle(.segmented)
                if durationMinutes == nil {
                    Text("Pick a session length.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
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
                Button(action: completeSetup) {
                    HStack {
                        Spacer()
                        Text(isOnboarding ? "Save & Continue" : "Save")
                        Spacer()
                    }
                    .fontWeight(.semibold)
                }
                .disabled(!canSave || isGenerating)
            }

            Section {
                Button(action: generate) {
                    HStack {
                        Spacer()
                        if isGenerating {
                            ProgressView()
                            Text("Building your plan…")
                        } else {
                            Image(systemName: "sparkles")
                            Text("Generate a Plan")
                        }
                        Spacer()
                    }
                }
                .disabled(!canSave || isGenerating)
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

    /// Seed the local day/duration selection from what the lifter last said,
    /// the first time this view appears, so editing setup starts from his
    /// stated schedule rather than silently resetting it. Both stay unset when
    /// he has never said.
    private func seedScheduleIfNeeded() {
        guard !hasSeededSchedule else { return }
        hasSeededSchedule = true
        selectedWeekdays = profile.preferredWeekdays
        durationMinutes = profile.preferredDurationMinutes
    }

    /// Writes what the lifter said to his profile and marks setup done. Setup
    /// is complete when he has answered — it waits on nothing else.
    private func completeSetup() {
        guard canSave else { return }
        profile.preferredWeekdays = selectedWeekdays
        profile.preferredDurationMinutes = durationMinutes
        profile.updatedAt = Date()
        profile.hasCompletedSetup = true
        do {
            try context.saveOrThrow()
            if !isOnboarding { dismiss() }
        } catch {
            errorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func generate() {
        guard let durationMinutes, !selectedWeekdays.isEmpty else { return }
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
