import SwiftUI
import SwiftData
import LiftingKit

/// One routine, block by block: the middle of the app and where it opens.
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
/// **What the block is for is behind the `info` mark, not above the weeks.**
/// The goal and the coach's note opened this screen, where they were read once
/// and scrolled past on every visit after that. They are what the block *is*,
/// which is worth having and is not worth the first screenful every time —
/// `RoutineInfoSheet` holds them, and the exercise sheet is reached by the same
/// mark for the same reason.
///
/// **What it depends on.** `TrainingPlan` and `WorkoutDay` from Store,
/// `ActiveWorkoutView` for the session, `RoutineInfoSheet` for what it is for, and
/// `RoutineListing` for the title.
struct RoutineView: View {

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
                let later = isLater(week)
                if !days.isEmpty {
                    Section {
                        SectionHeading(
                            BlockSelection.title(for: week), recessed: later)
                        ForEach(days) { day in
                            // A locked session is drawn, not offered. Wrapping
                            // it in a button that declines to act would leave a
                            // row that highlights under a thumb and then does
                            // nothing, which reads as the app having missed the
                            // tap rather than as the session being shut.
                            Group {
                                if later {
                                    DayRow(day: day, isLater: true)
                                } else {
                                    Button {
                                        openSession = day
                                    } label: {
                                        DayRow(day: day)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            // Each day its own panel. Sharing one per week made
                            // a week a single object with three names in it;
                            // a session is the thing being chosen, and the
                            // week is what it sits under.
                            .panelRow(
                                fillsPanel: true,
                                isRecorded: day.completedAt != nil,
                                recessed: later)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            // The end of the loop, said once. A routine whose last block is
            // filled in looks exactly like one mid-flight — every session
            // ticked, nothing to open — and the lifter has no way to tell
            // whether more is coming. The coach writes the next block having
            // read this one; this is the sentence that says it is his turn.
            if isSpent {
                Text("Every session is logged. Ask your coach for the next block.")
                    .note()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.surface)
        .navigationTitle(RoutineListing.title(of: plan))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // What the block is for lives behind this, not above the weeks.
            // Account is on the blocks list, which is the screen it belongs to:
            // it is about the lifter, not about the block he is reading.
            ToolbarItem(placement: .topBarTrailing) {
                // `info`, not `info.circle`: the toolbar draws the circle, and
                // a circular symbol inside a circular button is a ring in a
                // ring — it reads heavier than the back chevron opposite it,
                // which is a bare mark in the same glass. Same button, same
                // target; the glyph inside now matches.
                Button { showingInfo = true } label: {
                    Image(systemName: "info")
                }
                .accessibilityLabel("About this routine")
            }
        }
        .sheet(isPresented: $showingInfo) {
            NavigationStack { RoutineInfoSheet(plan: plan) }
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

    /// Whether every session of every block is finished, so there is nothing
    /// left to train until a plan arrives.
    ///
    /// The same fact the server reports as `nothingPrescribedBeyond`, read from
    /// the same place: the sessions themselves. Nothing here decides what should
    /// come next — only that nothing has.
    private var isSpent: Bool {
        let sessions = plan.orderedWeeks.flatMap(Self.trainingDays(of:))
        return !sessions.isEmpty && sessions.allSatisfy { $0.completedAt != nil }
    }

    /// Whether this week comes after the one he is on.
    ///
    /// The week he is on is the earliest still holding an unfinished session —
    /// read from the record rather than from the calendar, so a fortnight away
    /// does not move him on, and a session skipped in week one keeps week one
    /// current until he logs it or trains past it.
    ///
    /// **A later week is shut.** On Jon's call — *"I want them completely locked
    /// to the user"* — its sessions are drawn and cannot be opened. The cost is
    /// stated where it lands: a session trained ahead of schedule cannot be
    /// logged on the day it happened, and reaches the record when the week it
    /// belongs to becomes current. The lock is on the block a week sits in, not
    /// on the calendar, so finishing the week he is on opens the next one
    /// immediately.
    private func isLater(_ block: TrainingWeek) -> Bool {
        guard let current = BlockSelection.currentBlockOrdinal(in: plan.orderedWeeks)
        else { return false }
        return block.ordinal > current
    }

    /// The days of a week that prescribe work, in order.
    static func trainingDays(of block: TrainingWeek) -> [WorkoutDay] {
        block.orderedDays.filter { !$0.orderedExercises.isEmpty }
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
    /// Whether this session is in a week he has not reached. Drawn quieter, and
    /// shut: it carries a lock where an open row carries a chevron.
    var isLater: Bool = false

    private var title: String {
        SessionPhrasing.sessionTitle(focus: day.focus, weekday: day.weekday)
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
                .foregroundStyle(isLater ? Palette.muted : Palette.ink)
            Spacer()
            // Two marks doing two jobs. The check appears only where it is true
            // — a column of empty boxes beside every unlogged day would say
            // nothing — and the end of the row says what pressing it does: a
            // chevron where it opens, a lock where it does not. One glyph in
            // that slot, varying along one axis, which is the whole of the rule
            // for a mark inside a list.
            RecordedMark(isRecorded: day.completedAt != nil, showsEmpty: false)
            if isLater {
                Image(systemName: "lock.fill")
                    .font(.supersetSupport)
                    .foregroundStyle(Palette.muted)
            } else {
                DisclosureChevron()
            }
        }
        .padding(PanelMetrics.buttonInsets)
        // The panel's whole area, not the text's.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        // A shut row is not a button and must not be announced as one; what it
        // is instead is said in words, since the lock is a glyph.
        .accessibilityAddTraits(isLater ? [] : .isButton)
        .accessibilityHint(isLater ? "Locked until you reach this block" : "")
    }
}
