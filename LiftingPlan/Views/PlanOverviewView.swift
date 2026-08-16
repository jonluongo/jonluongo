import SwiftUI
import SwiftData

/// Shows the current week's plan as a list of day cards, with quick access into
/// each session.
///
/// Displays whatever plan is stored, exactly as stored, and shows an empty
/// state when there is none — the app does not write plans. Presented as the
/// first tab. Depends on: Store.
struct PlanOverviewView: View {
    let profile: UserProfile

    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    private var currentPlan: TrainingPlan? { plans.first }

    var body: some View {
        Group {
            if let plan = currentPlan {
                planList(plan)
            } else {
                ContentUnavailableView {
                    Label("No plan yet", systemImage: "dumbbell")
                } description: {
                    Text("Your training is planned in conversation with Claude. Once a plan is written, it lands here — your week, your sessions, and every set you log against them.\n\nUntil then there is nothing to show. Nothing to fill in either: tell Claude what you're after and he writes it down.")
                }
            }
        }
        .navigationTitle("This Week")
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
                        Label("No sessions in this plan", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("This plan has no training days yet. They appear here as they're added.")
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

}

/// Summary card at the top of the plan: goal, shape, and progress.
private struct PlanHeaderCard: View {
    let plan: TrainingPlan

    private var days: [WorkoutDay] { plan.orderedWeeks.first?.orderedDays ?? [] }
    private var completedCount: Int { days.filter { $0.completedAt != nil }.count }

    /// "3 days · 45 min", dropping the duration when the plan does not state one.
    private var shape: String {
        let dayText = "\(days.count) days"
        guard let minutes = plan.durationMinutes else { return dayText }
        return "\(dayText) · \(minutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !plan.goal.isEmpty {
                Text(plan.goal)
                    .font(.headline)
            } else {
                Text("No goal set")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text(shape)
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

    /// "Push · 5 exercises", dropping the focus when the plan did not label it.
    private var subtitle: String {
        let count = "\(day.orderedExercises.count) exercises"
        return day.focus.isEmpty ? count : "\(day.focus) · \(count)"
    }

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
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
