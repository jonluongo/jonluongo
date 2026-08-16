import SwiftUI

/// The whole block, a week at a time.
///
/// **What it does.** Lists every week the plan states, marks the one today
/// falls in and the ones that are deloads, and opens each to its sessions. It
/// is a list rather than a calendar grid on purpose: training is dense and
/// patterned, so a month of mostly-empty cells costs more space to say less
/// than a week does — and cannot say "week 4 is a deload", which is the thing
/// worth knowing about a block.
///
/// **How it is used.** Pushed from the Today screen's header, which is a link
/// rather than a tab: the block is what today is a part of, so it sits behind
/// today rather than beside it. `currentWeekOrdinal` comes from the same answer
/// the header was drawn from, so the two cannot disagree about which week it
/// is.
///
/// **What it depends on.** `TrainingPlan` and `TrainingWeek` from Store,
/// `PlanWeekSelection` for a week's title, and the shared row and note
/// components. It writes nothing.
struct BlockView: View {

    let plan: TrainingPlan
    let profile: UserProfile
    /// The week today falls in, or `nil` when today falls outside the block —
    /// before it starts, or after it has ended. Nothing is marked as current
    /// then, because nothing is.
    let currentWeekOrdinal: Int?

    private var weeks: [TrainingWeek] { plan.orderedWeeks }

    private var note: String? {
        plan.notes.flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        List {
            if !plan.goal.isEmpty || note != nil {
                Section {
                    if !plan.goal.isEmpty {
                        Text(plan.goal)
                            .font(.barbellTitle)
                    }
                    if let note {
                        CoachNoteView(note: note)
                    }
                }
            }

            if weeks.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No weeks yet", systemImage: "calendar")
                    } description: {
                        Text("This block's weeks appear here as they arrive.")
                    }
                }
            } else {
                Section("Weeks") {
                    ForEach(weeks) { week in
                        NavigationLink {
                            BlockWeekView(week: week, profile: profile)
                        } label: {
                            WeekRow(week: week, isCurrent: week.ordinal == currentWeekOrdinal)
                        }
                    }
                }
            }
        }
        .navigationTitle(plan.title.isEmpty ? "Block" : plan.title)
        .navigationBarTitleDisplayMode(.inline)
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

/// One week's sessions, in the order the plan prescribes them.
///
/// The row is `IconCircleRow`, the same shape the exercise header and the
/// finished-session row draw, and a completed session changes glyph and hue
/// together and nothing else. Depends on: Store, `SessionDetailView`.
struct BlockWeekView: View {

    let week: TrainingWeek
    let profile: UserProfile

    var body: some View {
        List {
            if week.orderedDays.isEmpty {
                ContentUnavailableView {
                    Label("No sessions in this week", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("This week has no training days yet. They appear here as they're added.")
                }
            } else {
                ForEach(week.orderedDays) { day in
                    NavigationLink {
                        SessionDetailView(day: day, profile: profile)
                    } label: {
                        SessionRow(day: day)
                    }
                }
            }
        }
        .navigationTitle(PlanWeekSelection.title(for: week))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One prescribed session as a row: the day it falls on, what it is for, and
/// whether it has been logged.
struct SessionRow: View {

    let day: WorkoutDay

    private var isLogged: Bool { day.completedAt != nil }

    /// "Push · 5 exercises", dropping the focus when the plan named none.
    private var subtitle: String {
        let count = TodayPhrasing.sessionShape(
            exercises: day.orderedExercises.count, durationMinutes: day.durationMinutes)
        return [day.focus.isEmpty ? nil : day.focus, count]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        IconCircleRow(
            systemImage: isLogged ? "checkmark" : "dumbbell.fill",
            tint: isLogged ? .green : .accentColor,
            title: day.weekday.fullName,
            subtitle: subtitle.isEmpty ? nil : subtitle
        )
    }
}
