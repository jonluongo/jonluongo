import SwiftUI
import LiftingKit

/// What a block is for, in the coach's words and in figures.
///
/// **What it does.** States the block: what it is called, what it is for, what he
/// wrote about it, and the shape he gave it — how many weeks, how many sessions,
/// which days, how long each runs, and how much is in the record.
///
/// **Why it is a sheet and not the top of the block.** The goal and the note sat
/// above the weeks, where they were read once and scrolled past every session
/// after that. They are what the block *is*, which is worth having and is not
/// worth the first screenful of every visit. The `info` mark on the bar is
/// where a lifter goes to ask.
///
/// **It states and never concludes.** No verdict on whether he is on schedule,
/// no projection, no "you should be here by now" — where he should be by week
/// three is a training judgement, and the app holds none. Every figure here is a
/// count of what the plan says or what the record holds.
///
/// **What it depends on.** `InfoSheet` for the chrome it shares with the
/// exercise sheet, `FactRow` for the stated facts, `CoachNoteView` for his
/// prose, and `RoutineListing` for the counts. It reads the block and writes
/// nothing.
struct RoutineInfoSheet: View {

    let plan: TrainingPlan

    @Environment(\.calendar) private var calendar

    private var note: String? {
        guard let notes = plan.notes, !notes.isEmpty else { return nil }
        return notes
    }

    /// The block's shape, as stated facts. A fact the plan did not state is
    /// absent rather than zero — a block that never said how long a session runs
    /// has not said it runs for no time.
    private var facts: [(String, String)] {
        var facts: [(String, String)] = []
        let weeks = plan.orderedWeeks
        if !weeks.isEmpty { facts.append(("Blocks", "\(weeks.count)")) }
        let days = weeks.flatMap(\.orderedDays)
        if !days.isEmpty {
            facts.append(("Sessions", "\(days.count)"))
            facts.append(("Logged", "\(days.count { $0.completedAt != nil })"))
        }
        let weekdays = plan.orderedWeekdays
        if !weekdays.isEmpty {
            facts.append(("Training days", weekdays.map(\.shortName).joined(separator: ", ")))
        }
        if let minutes = plan.durationMinutes {
            facts.append(("Session length", "\(minutes) min"))
        }
        return facts
    }

    var body: some View {
        InfoSheet(RoutineListing.title(of: plan)) {
            if !plan.goal.isEmpty || note != nil {
                Section {
                    if !plan.goal.isEmpty {
                        Text(plan.goal)
                            .font(.supersetTitle)
                            .foregroundStyle(Palette.ink)
                            .panelRow(note == nil ? .only : .first)
                            .listRowSeparator(.hidden)
                    }
                    if let note {
                        CoachNoteView(note: note)
                            .panelRow(plan.goal.isEmpty ? .only : .last)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            if !facts.isEmpty {
                Section {
                    SectionHeading("The routine")
                    ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                        FactRow(label: fact.0, value: fact.1)
                            .panelRow(.at(index, of: facts.count))
                            .listRowSeparator(.hidden)
                    }
                }
            }
        }
    }
}
