import SwiftUI
import SwiftData
import LiftingKit

/// One whole block, a week at a time — a block opened from the Blocks tab.
///
/// **What it does.** Names the block and repeats the coach's note, lists every
/// week the plan states, marks the one today falls in and the ones that are
/// deloads, and opens each to its sessions. It is a list rather than a calendar
/// grid on purpose: training is dense and patterned, so a month of mostly-empty
/// cells costs more space to say less than a week does — and cannot say "week 4
/// is a deload", which is the thing worth knowing about a block.
///
/// **How it is used.** Pushed from `PlansView` with the block to draw. It used
/// to be the tab itself and read the newest block out of the store, which is what
/// made every earlier block unreachable; it is now handed the block it shows, so
/// the same screen serves the current one and every one before it.
///
/// **What it depends on.** `TrainingPlan` and `TrainingWeek` from Store,
/// `TodayInPlan` from Services for which week is current, `PlansListing` for the
/// block's name, `PlanWeekSelection` for a week's title, and the shared row and
/// note components. It writes nothing.
struct BlockView: View {

    let plan: TrainingPlan
    let profile: UserProfile

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar

    /// When "today" is, re-read whenever the app comes back to the screen, so a
    /// phone left open overnight does not keep marking last week as this one.
    @State private var now = Date()

    var body: some View {
        weeks(of: plan)
            .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle(PlansListing.title(of: plan))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
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
                let hasNote = note(plan) != nil
                Section {
                    if !plan.goal.isEmpty {
                        Text(plan.goal)
                            .font(.barbellTitle)
                            .foregroundStyle(Palette.ink)
                            .panelRow(hasNote ? .first : .only)
                            .listRowSeparator(.hidden)
                    }
                    if let note = note(plan) {
                        CoachNoteView(note: note)
                            .panelRow(plan.goal.isEmpty ? .only : .last)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            if ordered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No weeks yet", systemImage: "calendar")
                    }
                }
            } else {
                Section {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, week in
                        NavigationLink {
                            BlockWeekView(week: week, unit: profile.displayUnit)
                        } label: {
                            WeekRow(week: week, isCurrent: week.ordinal == current)
                        }
                        .panelRow(.at(index, of: ordered.count))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    SectionHeading("Weeks")
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
