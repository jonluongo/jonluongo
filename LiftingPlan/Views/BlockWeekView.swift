import SwiftUI
import LiftingKit

/// One week of the block, in full: each session it prescribes and each exercise
/// inside it.
///
/// **What it does.** Draws a section per training day — the day, what it is for,
/// whether it has been logged — and under it every exercise the plan asks for,
/// each of which opens its own record.
///
/// **The sessions are here rather than one tap further down.** There used to be
/// a screen below this that previewed a single day, and it was deleted for
/// showing the same session Today shows. A week that only listed its days would
/// need that screen back to say anything, so the week says it: this is the plan
/// being read, seven days at a time, with no button to start any of it. Today
/// remains the only screen that trains a session.
///
/// **How it is used.** Pushed from `BlockView`, inside the Plans tab's stack.
/// **What it depends on.** `TrainingWeek` and `WorkoutDay` from Store,
/// `PlanWeekSelection` for the title, and the shared row components. It writes
/// nothing.
struct BlockWeekView: View {

    let week: TrainingWeek
    /// The lifter's display unit, carried down to the prescriptions.
    let unit: MassUnit

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
                    Section {
                        SessionRow(day: day)
                            .panelRow(.first)
                            .listRowSeparator(.hidden)
                        exercises(of: day)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle(PlanWeekSelection.title(for: week))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What the day prescribes, or the fact that it prescribes nothing yet —
    /// said plainly rather than left as a section with a heading and no body.
    @ViewBuilder
    private func exercises(of day: WorkoutDay) -> some View {
        if day.orderedExercises.isEmpty {
            Text("No exercises yet.")
                .font(.barbellSupport)
                .foregroundStyle(Palette.muted)
                .panelRow(.last)
                .listRowSeparator(.hidden)
        } else {
            ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                Group {
                    switch entry {
                    case .exercise(let exercise):
                        ExerciseDetailLink(exercise: exercise, unit: unit)
                    case .group(let group):
                        PrescribedGroupRows(group: group, unit: unit)
                    }
                }
                .panelRow(index == day.entries.count - 1 ? .last : .middle)
                .listRowSeparator(.hidden)
            }
        }
    }
}

/// One prescribed session as a row: the day it falls on, what it is for, and
/// whether it has been logged.
///
/// It heads its own section rather than leading somewhere. A section header
/// proper is drawn small, grey and uppercased, which is how a list says "column
/// of a table"; this is the name of a training day, so it is a row.
struct SessionRow: View {

    let day: WorkoutDay

    private var isLogged: Bool { day.completedAt != nil }

    /// "Push · 60 min", dropping either part the plan did not state.
    ///
    /// **It no longer counts the exercises.** The count sat one row above the
    /// list it was counting, so it told the reader something the next inch of
    /// screen already showed. The session's length is the one fact on this line
    /// that is nowhere else on the screen, so it stayed.
    private var subtitle: String {
        [day.focus.isEmpty ? nil : day.focus, day.durationMinutes.map { "\($0) min" }]
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
