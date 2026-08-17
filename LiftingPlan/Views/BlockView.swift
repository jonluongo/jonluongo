import SwiftUI
import SwiftData
import LiftingKit

/// The whole block, a week at a time — the Plan tab.
///
/// **What it does.** Names the block and repeats the coach's note, lists every
/// week the plan states, marks the one today falls in and the ones that are
/// deloads, and opens each to its sessions. It is a list rather than a calendar
/// grid on purpose: training is dense and patterned, so a month of mostly-empty
/// cells costs more space to say less than a week does — and cannot say "week 4
/// is a deload", which is the thing worth knowing about a block.
///
/// **How it is used.** The second tab. It used to be pushed from a link on
/// Today; the block is not a detail of the day, it is the thing the day is part
/// of, so it stands beside Today rather than behind it and the link went. It
/// reads the store directly for the same reason Today does — a tab is addressed
/// by nothing.
///
/// **What it depends on.** `TrainingPlan` and `TrainingWeek` from Store,
/// `TodayInPlan` from Services for which week is current, `PlanWeekSelection`
/// for a week's title, and the shared row and note components. It writes
/// nothing.
struct BlockView: View {

    let profile: UserProfile

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// When "today" is, re-read whenever the app comes back to the screen, so a
    /// phone left open overnight does not keep marking last week as this one.
    @State private var now = Date()

    private var plan: TrainingPlan? { plans.first }

    var body: some View {
        Group {
            if let plan {
                weeks(of: plan)
            } else {
                NoBlockView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
    }

    /// What the plan called itself, or what it is for when it went unnamed.
    private var title: String {
        guard let plan else { return "Plan" }
        if !plan.title.isEmpty { return plan.title }
        if !plan.goal.isEmpty { return plan.goal }
        return "Plan"
    }

    private func note(_ plan: TrainingPlan) -> String? {
        plan.notes.flatMap { $0.isEmpty ? nil : $0 }
    }

    @ViewBuilder
    private func weeks(of plan: TrainingPlan) -> some View {
        let ordered = plan.orderedWeeks
        let current = currentWeekOrdinal(plan)
        List {
            if !plan.goal.isEmpty || note(plan) != nil {
                Section {
                    if !plan.goal.isEmpty {
                        Text(plan.goal)
                            .font(.barbellTitle)
                    }
                    if let note = note(plan) {
                        CoachNoteView(note: note)
                    }
                }
            }

            if ordered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No weeks yet", systemImage: "calendar")
                    } description: {
                        Text("This block's weeks appear here as they arrive.")
                    }
                }
            } else {
                Section("Weeks") {
                    ForEach(ordered) { week in
                        NavigationLink {
                            BlockWeekView(week: week, unit: profile.displayUnit)
                        } label: {
                            WeekRow(week: week, isCurrent: week.ordinal == current)
                        }
                    }
                }
            }
        }
    }

    /// The week today falls in, or `nil` when today falls outside the block —
    /// before it starts, or after it has ended. Nothing is marked as current
    /// then, because nothing is.
    private func currentWeekOrdinal(_ plan: TrainingPlan) -> Int? {
        let standing = TodayInPlan.resolve(plan, on: now, calendar: calendar).standing
        return standing.session?.week.ordinal ?? standing.rest?.ordinal
    }
}

/// One week in the block list.
///
/// A deload changes glyph and tint together, and says the word as well — the
/// colour is never the only thing carrying it. Which week is current is said in
/// the line under the title rather than by a highlight, for the same reason.
private struct WeekRow: View {

    let week: TrainingWeek
    let isCurrent: Bool

    private var days: [WorkoutDay] { week.orderedDays }
    private var loggedCount: Int { days.filter { $0.completedAt != nil }.count }

    /// "This week · 3 sessions · 2 logged", dropping each part that has nothing
    /// to state. A week with no sessions says so rather than claiming zero of
    /// something.
    private var subtitle: String {
        var parts: [String] = []
        if isCurrent { parts.append("This week") }
        if days.isEmpty {
            parts.append("No sessions yet")
        } else {
            parts.append("\(days.count) session\(days.count == 1 ? "" : "s")")
            if loggedCount > 0 { parts.append("\(loggedCount) logged") }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        IconCircleRow(
            systemImage: week.isDeload ? "moon.fill" : "dumbbell.fill",
            tint: week.isDeload ? .secondary : .accentColor,
            title: PlanWeekSelection.title(for: week),
            subtitle: subtitle
        )
    }
}
