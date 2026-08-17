import SwiftUI

/// The screens the block is read through, as values a navigation path can hold.
///
/// **What it does.** Names the two things that can sit over the Today screen:
/// the block, and one week of it. They are values rather than destinations
/// because the Today screen has to be able to empty its own path — a session
/// chosen inside the block is shown *there*, so the block closes behind it.
///
/// **How it is used.** `NavigationLink(value:)` here, `navigationDestination`
/// on `TodayView`. **What it depends on.** `TrainingWeek` from Store.
enum BlockDestination: Hashable {

    /// The whole block, marking the week the day being read falls in. The
    /// ordinal travels with the destination so the pushed screen keeps the week
    /// it was opened against, rather than re-deriving it from a day the lifter
    /// may since have swiped away from.
    case block(currentWeekOrdinal: Int?)

    /// One week's sessions.
    case week(TrainingWeek)
}

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
    /// The week today falls in, or `nil` when today falls outside the block —
    /// before it starts, or after it has ended. Nothing is marked as current
    /// then, because nothing is.
    let currentWeekOrdinal: Int?
    /// What to do with a session the lifter picks out down here: show it on the
    /// screen this one was pushed from. Passed all the way down rather than
    /// acted on locally, because the day is shown *there*.
    let show: (WorkoutDay) -> Void

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
                        NavigationLink(value: BlockDestination.week(week)) {
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
/// together and nothing else.
///
/// **A session opens on the Today screen, not here.** There used to be a third
/// screen below this one that previewed a day and offered to start it; Today now
/// shows any day of the block in full, so the preview was the same session read
/// twice. Tapping a session selects that day up there and closes the block
/// behind it. Depends on: Store, `PlanWeekSelection`.
struct BlockWeekView: View {

    let week: TrainingWeek
    /// Where a tapped session goes — see `BlockView.show`.
    let show: (WorkoutDay) -> Void

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
                    Button { show(day) } label: {
                        SessionRow(day: day)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows this session on Today")
                }
            }
        }
        .navigationTitle(PlanWeekSelection.title(for: week))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One prescribed session as a row: the day it falls on, what it is for,
/// whether it has been logged, and a chevron saying it goes somewhere.
///
/// Where it goes is the Today screen, showing that day — so the chevron is
/// honest about there being a destination and only unusual in that the
/// destination is behind it rather than in front. A row that acts on a tap and
/// looks inert is the worse of the two.
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
        ) {
            Image(systemName: "chevron.forward")
                .font(.barbellLabel)
                .foregroundStyle(.secondary)
        }
    }
}
