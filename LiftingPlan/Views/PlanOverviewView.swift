import SwiftUI
import SwiftData

/// Shows the stored block a week at a time, with quick access into each session.
///
/// A block may run several weeks and they may differ — a deload prescribes
/// genuinely less work than the week before it — so every week Claude wrote is
/// reachable here through the week picker. The screen opens on the week
/// `PlanWeekSelection` derives from what has actually been logged, so finishing
/// the last session of week 1 moves it on to week 2 rather than leaving it
/// reporting a finished block for the rest of the month.
///
/// Displays whatever plan is stored, exactly as stored, and shows an empty
/// state when there is none — the app does not write plans. Presented as the
/// first tab. Depends on: Store, `PlanWeekSelection`.
struct PlanOverviewView: View {
    let profile: UserProfile

    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// The week the lifter has picked. `nil` means he has not picked one, in
    /// which case the derived current week is shown — so the screen keeps
    /// moving with the log until he says otherwise.
    @State private var selectedWeekOrdinal: Int?

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
        .navigationTitle("Plan")
    }

    @ViewBuilder
    private func planList(_ plan: TrainingPlan) -> some View {
        let weeks = plan.orderedWeeks
        let week = shownWeek(in: weeks)
        let days = week?.orderedDays ?? []
        List {
            Section {
                PlanHeaderCard(plan: plan, week: week, weekCount: weeks.count)
            }

            // Only when there is a choice to make. One week is not a picker.
            if weeks.count > 1 {
                Section {
                    Picker("Week", selection: weekBinding(in: weeks)) {
                        ForEach(weeks) { candidate in
                            Text(PlanWeekSelection.title(for: candidate)).tag(candidate.ordinal)
                        }
                    }
                }
            }

            if days.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No sessions in this week", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("This week has no training days yet. They appear here as they're added.")
                    }
                }
            } else {
                Section(week.map(PlanWeekSelection.title(for:)) ?? "Sessions") {
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

    /// The week on screen: the one the lifter picked, or — while he has picked
    /// none, or has picked one the plan no longer contains — the one derived
    /// from the log.
    private func shownWeek(in weeks: [TrainingWeek]) -> TrainingWeek? {
        let ordinal = selectedWeekOrdinal ?? PlanWeekSelection.currentWeekOrdinal(in: weeks)
        return weeks.first { $0.ordinal == ordinal } ?? weeks.first
    }

    private func weekBinding(in weeks: [TrainingWeek]) -> Binding<Int> {
        Binding(
            get: { shownWeek(in: weeks)?.ordinal ?? 0 },
            set: { selectedWeekOrdinal = $0 }
        )
    }
}

/// Summary card at the top of the plan: the goal Claude recorded, where in the
/// block this week sits, and how much of that week is logged.
///
/// Everything here describes the week actually on screen, so the progress line
/// cannot outlive the week it counted.
private struct PlanHeaderCard: View {
    let plan: TrainingPlan
    let week: TrainingWeek?
    let weekCount: Int

    private var days: [WorkoutDay] { week?.orderedDays ?? [] }
    private var completedCount: Int { days.filter { $0.completedAt != nil }.count }

    /// "Week 2 of 4 · Deload" — the block's length as the plan states it, or as
    /// many weeks as have actually arrived when it states none.
    private var position: String? {
        guard let week else { return nil }
        let total = plan.weekCount ?? weekCount
        let base = total > 1 ? "Week \(week.ordinal) of \(total)" : "Week \(week.ordinal)"
        if !week.label.isEmpty { return "\(base) · \(week.label)" }
        if week.isDeload { return "\(base) · Deload" }
        return base
    }

    /// "3 days · 45 min", dropping the duration when the plan does not state one.
    private var shape: String {
        let dayText = "\(days.count) days"
        guard let minutes = plan.durationMinutes else { return dayText }
        return "\(dayText) · \(minutes) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // No placeholder when there is no goal: the goal is Claude's to
            // record, and an empty field would read as one the lifter forgot
            // to fill in.
            if !plan.goal.isEmpty {
                Text(plan.goal)
                    .font(.headline)
            }
            if let position {
                Text(position)
                    .font(.subheadline.weight(.medium))
            }

            // A week with no days asserts nothing — not "0 days", and not a
            // progress bar confidently reading 0% of nothing.
            if !days.isEmpty {
                Text(shape)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(completedCount), total: Double(days.count)) {
                    Text("\(completedCount) of \(days.count) sessions done")
                        .font(.caption)
                }
                .tint(.accentColor)
            }
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
