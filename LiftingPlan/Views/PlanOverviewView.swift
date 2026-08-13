import SwiftUI
import SwiftData

/// Shows the current week's plan as a list of day cards, with regeneration and
/// quick access into each session.
struct PlanOverviewView: View {
    let preferences: TrainingPreferences

    @Environment(\.modelContext) private var context
    @Environment(PlanGenerator.self) private var generator
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

    @State private var isGenerating = false
    @State private var showingEditSetup = false

    private var currentPlan: WorkoutPlan? { plans.first }

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
                SetupView(preferences: preferences, isOnboarding: false)
            }
        }
        .overlay {
            if isGenerating {
                generatingOverlay
            }
        }
    }

    @ViewBuilder
    private func planList(_ plan: WorkoutPlan) -> some View {
        List {
            Section {
                PlanHeaderCard(plan: plan)
            }
            Section("Your week") {
                ForEach(plan.orderedSessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        SessionRow(session: session)
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
            await PlanCoordinator.generateAndStore(
                preferences: preferences,
                generator: generator,
                context: context,
                existingPlans: plans
            )
            isGenerating = false
        }
    }
}

/// Summary card at the top of the plan: goal, source, and progress.
private struct PlanHeaderCard: View {
    let plan: WorkoutPlan

    private var completedCount: Int {
        plan.sessions.filter(\.isCompleted).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !plan.goalSnapshot.isEmpty {
                Text(plan.goalSnapshot)
                    .font(.headline)
            } else {
                Text("General strength & muscle")
                    .font(.headline)
            }
            HStack(spacing: 8) {
                Label(plan.wasModelGenerated ? "AI-tailored" : "Template", systemImage: plan.wasModelGenerated ? "sparkles" : "square.grid.2x2")
                Text("·")
                Text("\(plan.sessions.count) days · \(plan.durationMinutes) min")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: Double(completedCount), total: Double(max(plan.sessions.count, 1))) {
                Text("\(completedCount) of \(plan.sessions.count) sessions done")
                    .font(.caption)
            }
            .tint(.accentColor)
        }
        .padding(.vertical, 4)
    }
}

/// A single day row in the week list.
private struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(session.isCompleted ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: session.isCompleted ? "checkmark" : "dumbbell.fill")
                    .foregroundStyle(session.isCompleted ? .green : .accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.weekday.fullName).font(.headline)
                Text("\(session.focus) · \(session.exercises.count) exercises")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
