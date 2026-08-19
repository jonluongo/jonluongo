import SwiftUI
import SwiftData
import LiftingKit

/// One block, week by week: the middle of the app and where it opens.
///
/// **What it does.** Lists every training day the block prescribes, grouped
/// under the week it belongs to, and opens the session when one is tapped. The
/// day is named by what Claude called it — `Pull`, `Legs` — because that is what
/// the session is; the weekday survives only as the fallback when he named it
/// nothing.
///
/// **Only training days.** A day the block prescribes no exercises on is not a
/// row: there is nothing to tap and nothing to log, and listing it would be the
/// screen offering work that does not exist.
///
/// **The session is a sheet.** It is a thing entered, done and left, which is
/// what a sheet is for — and leaving it puts the lifter back where he chose it,
/// with that day now marked. The app opened straight into the session before
/// this, with the week's remaining workouts swiped between; that could show what
/// was left but never what was coming, so looking ahead or back was impossible.
///
/// **What it depends on.** `TrainingPlan` and `WorkoutDay` from Store,
/// `ActiveWorkoutView` for the session, and `PlansListing` for the title.
struct BlockView: View {

    let plan: TrainingPlan
    let profile: UserProfile

    /// The session being logged, or `nil`.
    @State private var openSession: WorkoutDay?

    var body: some View {
        List {
            // What the block is for, and what Claude said about it.
            //
            // The goal anchors the note. Without it the paragraph opened the
            // screen with nothing to attach to — a instruction about reps and
            // failure, floating above a list of days, with no statement of what
            // any of it is meant to achieve. The goal is the block's subject and
            // the note is his commentary on it, so they are one panel.
            if !plan.goal.isEmpty || (plan.notes.map { !$0.isEmpty } ?? false) {
                let hasNote = plan.notes.map { !$0.isEmpty } ?? false
                Section {
                    if !plan.goal.isEmpty {
                        Text(plan.goal)
                            .font(.supersetTitle)
                            .foregroundStyle(Palette.ink)
                            .panelRow(hasNote ? .first : .only)
                            .listRowSeparator(.hidden)
                    }
                    if let note = plan.notes, !note.isEmpty {
                        CoachNoteView(note: note)
                            .panelRow(plan.goal.isEmpty ? .only : .last)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            ForEach(plan.orderedWeeks) { week in
                let days = Self.trainingDays(of: week)
                if !days.isEmpty {
                    Section {
                        SectionHeading(PlanWeekSelection.title(for: week))
                        ForEach(days) { day in
                            Button {
                                openSession = day
                            } label: {
                                DayRow(day: day)
                            }
                            .buttonStyle(.plain)
                            // Each day its own panel. Sharing one per week made
                            // a week a single object with three names in it;
                            // a session is the thing being chosen, and the
                            // week is what it sits under.
                            .panelRow(.only, fillsPanel: true)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle(PlansListing.title(of: plan))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { AccountToolbarItem(profile: profile) }
        .fullScreenCover(item: $openSession) { session in
            // The session carries a toolbar — the way out, and the elapsed
            // clock — and a toolbar draws nothing without a navigation
            // container. It had one when it was the app's root and lost it when
            // it became a page of a pager; presented as a cover with no stack it
            // rendered no X at all, so a lifter who opened a workout could not
            // leave it.
            NavigationStack {
                ActiveWorkoutView(day: session, profile: profile)
            }
        }
    }

    /// The days of a week that prescribe work, in order.
    static func trainingDays(of week: TrainingWeek) -> [WorkoutDay] {
        week.orderedDays.filter { !$0.orderedExercises.isEmpty }
    }
}

/// One training day: what Claude called it, how long it runs, and whether it is
/// in the record.
///
/// The mark is the only thing distinguishing a logged day from one still to
/// come, and it is a mark rather than a colour on the title — a session already
/// trained is still worth opening to correct.
private struct DayRow: View {

    let day: WorkoutDay

    private var title: String {
        TodayPhrasing.sessionTitle(focus: day.focus, weekday: day.weekday)
    }

    /// The movements themselves, which is what the session actually is.
    ///
    /// **There is no icon here and cannot be one.** The day's name is whatever
    /// Claude called it — `Push`, `Upper A`, `Chest & Back` — so a glyph per
    /// session would mean the app deciding what a session trains from words it
    /// does not control, and one glyph for all of them is a mark identical
    /// everywhere it appears, which is decoration. The movements say it without
    /// guessing.
    ///
    /// The movements, in order, on one line.
    ///
    /// **In full, because shortening them lied.** Keeping the last two words of
    /// each turned "Barbell Bench Press" and "Dumbbell Incline Bench Press" into
    /// the same string, so a session listed one movement twice and hid another —
    /// the row claiming a session the block does not prescribe. The line runs to
    /// the edge and truncates there instead, which says *and more* without
    /// naming anything wrongly.
    ///
    /// It used to be two names plus `+4`, over a line counting the exercises and
    /// the minutes — three lines of grey wrapping unevenly under the name, with
    /// the mark floating against the middle of them. The count said in a figure
    /// what the names say concretely; the names stayed.
    private var movements: String? {
        let names = day.orderedExercises.map(\.displayName)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack(spacing: Spacing.standard) {
                Text(title)
                    .font(.supersetTitle)
                    .foregroundStyle(Palette.ink)
                Spacer()
                // Two marks doing two jobs. The check appears only where it is
                // true — a column of empty boxes beside every unlogged day
                // would say nothing — and the chevron appears on every row,
                // because every row opens something. The blocks list draws the
                // same chevron, so a session and a block are chosen the same
                // way.
                RecordedMark(isRecorded: day.completedAt != nil, showsEmpty: false)
                DisclosureChevron()
            }
            if let movements {
                Text(movements)
                    .font(.supersetSupport)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(PanelMetrics.buttonInsets)
        // The panel's whole area, not the text's.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
