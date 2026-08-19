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
/// **What the block is for is behind the `info.circle`, not above the weeks.**
/// The goal and the coach's note opened this screen, where they were read once
/// and scrolled past on every visit after that. They are what the block *is*,
/// which is worth having and is not worth the first screenful every time —
/// `BlockInfoSheet` holds them, and the exercise sheet is reached by the same
/// mark for the same reason.
///
/// **What it depends on.** `TrainingPlan` and `WorkoutDay` from Store,
/// `ActiveWorkoutView` for the session, `BlockInfoSheet` for what it is for, and
/// `PlansListing` for the title.
struct BlockView: View {

    let plan: TrainingPlan
    let profile: UserProfile

    /// The session being logged, or `nil`.
    @State private var openSession: WorkoutDay?
    /// Whether what the block is for is being read.
    @State private var showingInfo = false

    var body: some View {
        List {
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
                            .panelRow(
                                .only, fillsPanel: true,
                                isRecorded: day.completedAt != nil)
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
        .toolbar {
            // What the block is for lives behind this, not above the weeks.
            // Account is on the blocks list, which is the screen it belongs to:
            // it is about the lifter, not about the block he is reading.
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingInfo = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About this block")
            }
        }
        .sheet(isPresented: $showingInfo) {
            NavigationStack { BlockInfoSheet(plan: plan) }
                .presentationDragIndicator(.visible)
        }
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

/// One training day: what Claude called it, and whether it is in the record.
///
/// **The name, and nothing under it.** The row listed the session's movements —
/// `Barbell Bench Press · Dumbbell Seated Overhea…` — which crowded the two
/// marks at the other end and truncated before it finished naming the second
/// one. What the session is called is what a lifter is choosing between here;
/// what is in it is one tap away, in full.
///
/// **The mark is the plan's, never the app's.** A glyph inferred from the day's
/// name would be the app deciding what a session trains from words it does not
/// control, and one glyph for all of them is a mark identical everywhere it
/// appears. So the coach chooses from a closed set the app publishes, the same
/// way he chooses exercises from a catalog he did not write — and a day he
/// marked nothing carries nothing.
private struct DayRow: View {

    let day: WorkoutDay

    private var title: String {
        TodayPhrasing.sessionTitle(focus: day.focus, weekday: day.weekday)
    }

    var body: some View {
        HStack(spacing: Spacing.standard) {
            // Only where the plan chose one. The app never picks a mark for a
            // session, so a day the coach left unmarked carries none and the
            // name starts at the panel's edge as it always did.
            if let icon = day.icon {
                SessionIconView(icon: icon)
            }
            Text(title)
                .font(.supersetTitle)
                .foregroundStyle(Palette.ink)
            Spacer()
            // Two marks doing two jobs. The check appears only where it is true
            // — a column of empty boxes beside every unlogged day would say
            // nothing — and the chevron on every row, because every row opens
            // something. The panel's own ground carries it a third time, which
            // is the one that reads without looking at the row.
            RecordedMark(isRecorded: day.completedAt != nil, showsEmpty: false)
            DisclosureChevron()
        }
        .padding(PanelMetrics.buttonInsets)
        // The panel's whole area, not the text's.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
