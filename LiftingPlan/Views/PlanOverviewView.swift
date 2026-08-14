import SwiftUI
import SwiftData

/// Shows the current week's plan as a list of day cards, with regeneration and
/// quick access into each session.
struct PlanOverviewView: View {
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(PlanGenerator.self) private var generator
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    @State private var isGenerating = false
    @State private var showingEditSetup = false
    @State private var errorMessage: String?

    private var currentPlan: TrainingPlan? { plans.first }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        Group {
            if let plan = currentPlan {
                planList(plan)
            } else {
                ContentUnavailableView {
                    Label("No plan yet", systemImage: "dumbbell")
                } description: {
                    Text("Generate a plan to get started.")
                } actions: {
                    Button("Generate Plan", action: regenerate)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("This Week")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        regenerate()
                    } label: {
                        Label("Regenerate Week", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        showingEditSetup = true
                    } label: {
                        Label("Edit Setup", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isGenerating)
            }
        }
        .sheet(isPresented: $showingEditSetup) {
            NavigationStack {
                SetupView(profile: profile, isOnboarding: false)
            }
        }
        .overlay {
            if isGenerating {
                generatingOverlay
            }
        }
        .alert("Couldn't Save", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func planList(_ plan: TrainingPlan) -> some View {
        let days = plan.orderedWeeks.first?.orderedDays ?? []
        List {
            Section {
                PlanHeaderCard(plan: plan)
            }
            if days.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No workouts yet", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("Plan generation is being rebuilt against the full exercise catalog. Adjust your setup and regenerate once it's ready.")
                    }
                }
            } else {
                Section("Your week") {
                    ForEach(days) { day in
                        NavigationLink {
                            SessionDetailView(day: day, profile: profile)
                        } label: {
                            WorkoutDayRow(day: day)
                        }
                    }
                }
            }
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Building your plan…").font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }

    private func regenerate() {
        isGenerating = true
        Task {
            do {
                try await PlanCoordinator.generateAndStore(
                    profile: profile,
                    weekdays: currentPlan?.weekdays ?? [.monday, .wednesday, .friday],
                    durationMinutes: currentPlan?.durationMinutes ?? 45,
                    generator: generator,
                    context: context,
                    existingPlans: plans
                )
            } catch {
                errorMessage = (error as? PersistenceError)?.errorDescription ?? error.localizedDescription
            }
            isGenerating = false
        }
    }
}

/// Summary card at the top of the plan: goal, source, and progress.
private struct PlanHeaderCard: View {
    let plan: TrainingPlan

    private var days: [WorkoutDay] { plan.orderedWeeks.first?.orderedDays ?? [] }
    private var completedCount: Int { days.filter { $0.completedAt != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !plan.goal.isEmpty {
                Text(plan.goal)
                    .font(.headline)
            } else {
                Text("General strength & muscle")
                    .font(.headline)
            }
            HStack(spacing: 8) {
                Label(plan.wasModelGenerated ? "AI-tailored" : "Template", systemImage: plan.wasModelGenerated ? "sparkles" : "square.grid.2x2")
                Text("·")
                Text("\(days.count) days · \(plan.durationMinutes) min")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: Double(completedCount), total: Double(max(days.count, 1))) {
                Text("\(completedCount) of \(days.count) sessions done")
                    .font(.caption)
            }
            .tint(.accentColor)
        }
        .padding(.vertical, 4)
    }
}

/// A single day row in the week list.
private struct WorkoutDayRow: View {
    let day: WorkoutDay

    private var isCompleted: Bool { day.completedAt != nil }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: isCompleted ? "checkmark" : "dumbbell.fill")
                    .foregroundStyle(isCompleted ? .green : .accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day.weekday.fullName).font(.headline)
                Text("\(day.focus) · \(day.orderedExercises.count) exercises")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
