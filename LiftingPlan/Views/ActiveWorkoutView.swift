import SwiftUI
import SwiftData
import LiftingKit

/// The guided workout, spreadsheet-style: every exercise in one scroll, each with
/// an editable table of sets (set · previous · weight · reps · ✓). Checking a set
/// off starts the rest/pace timer, which floats in a bar at the bottom.
struct ActiveWorkoutView: View {
    let day: WorkoutDay
    let profile: UserProfile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimerModel.self) private var restTimer
    /// The lifter's own clock: whether it runs at all, and how long on each
    /// exercise. Not the prescription, and not in the store.
    @Environment(RestPreferences.self) private var restPreferences
    /// The outbox the finished session is sent through. Optional so a preview
    /// need not supply one; the app always does.
    @Environment(SnapshotOutbox.self) private var snapshotOutbox: SnapshotOutbox?
    @Query(sort: \TrainingPlan.startDate, order: .reverse) private var plans: [TrainingPlan]

    /// The clock being edited — an exercise's, or a group's — and the exercise
    /// being read about.
    @State private var restEditing: RestTarget?
    @State private var infoExercise: PlannedExercise?
    /// The exercise whose own note the lifter is writing.
    @State private var noteExercise: PlannedExercise?
    /// Whether the rest clock has been opened to its full size.
    @State private var showingRest = false
    /// The set to bring into view, set when a group's round moves on.
    @State private var scrollTarget: PersistentIdentifier?
    @State private var errorMessage: String?

    private var exercises: [PlannedExercise] { day.orderedExercises }

    /// The session in the order it is trained: an exercise, or a group of them
    /// performed as rounds. The grouping was prescribed; nothing here makes one.
    private var entries: [SessionEntry] { day.entries }

    /// Whether this session has been marked done. Not derived from how much of
    /// it is filled in: a lifter who stops at three sets of four has finished,
    /// and one resting between sets has not, and nothing in the record can tell
    /// those apart. Only he can, which is what the button is for.
    private var isLogged: Bool { day.completedAt != nil }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    var body: some View {
        ScrollViewReader { scroller in
            List {
                if exercises.isEmpty {
                    ContentUnavailableView {
                        Label("No exercises", systemImage: "dumbbell.fill")
                    }
                } else {
                    ForEach(entries) { entry in
                        switch entry {
                        case .exercise(let exercise): section(for: exercise)
                        case .group(let group): section(for: group)
                        }
                    }
                    // Past the last set, which is where a lifter who has
                    // finished arrives. It used to be top right, where it was
                    // pressed as a way out of the screen.
                    SessionFinishSection(
                        isLogged: isLogged, unloggedSetCount: day.unloggedSetCount,
                        onFinish: { writeAndShare(log.finish) },
                        onUnfinish: { writeAndShare(log.unfinish) })
                }

            }
            // Plain, with the panel drawn by the rows themselves — see
            // `panelRow`. Inset-grouped would draw its own panel underneath, at
            // its own corner radius, and the radius is the point: the system's
            // is drawn for cards of content and these hold a table of figures.
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .scrollDismissesKeyboard(.interactively)
            // No title. It was the session's name, large, filling the band this
            // screen used to waste — but the name is on the card the lifter
            // came from and on every screen that led here, and a heading over a
            // session he is already inside answers a question nobody has. An
            // inline bar with nothing in the middle collapses to its own height,
            // which is tighter than the large title was and tighter than the
            // empty band before it.
            .navigationBarTitleDisplayMode(.inline)
            // The one place the screen moves itself: a group's next set, when
            // the last one was ticked. `scrollTarget` is cleared as soon as it
            // is used, so nothing is held that would scroll again on a redraw.
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy) { scroller.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
            .toolbar {
                ActiveWorkoutToolbar()
                // The way out, back where it belongs. Top right means dismiss
                // and only dismiss now: Finish lives under the last set, so the
                // corner that once marked an untouched session as trained can
                // safely hold the thing everyone reads it as.
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close workout")
                }
                // How long he has been training, counting from the first ticked
                // set. It lived in the header of a screen that no longer exists,
                // and went with it — another thing the restructure dropped
                // rather than decided.
                // The title's place, because it is the bar's own line. As a
                // leading item it was given a small fixed capsule and truncated
                // to "1…", which is a clock saying nothing.
                ToolbarItem(placement: .principal) {
                    if let startedAt = day.startedAt, let lastLoggedAt = day.lastLoggedAt {
                        SessionClock(
                            startedAt: startedAt, lastLoggedAt: lastLoggedAt,
                            finishedAt: day.completedAt)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if restTimer.isRunning {
                    // The bar is the clock in a glance; tapping it is the clock
                    // to look at, with the next set under it. Rest is the one
                    // moment in a session with nothing else to do, which is why
                    // it is worth a surface of its own.
                    //
                    // The bar owns which part of itself opens it: wrapping the
                    // whole thing in a button put `−15`, `+15` and skip inside
                    // another button, and a tap on one of those is then a tap
                    // whose meaning depends on which the system decides it hit.
                    RestTimerBar(restTimer: restTimer) { showingRest = true }
                }
            }
            .sheet(isPresented: $showingRest) {
                RestSheet(
                    day: day, profile: profile, plans: plans, restTimer: restTimer,
                    onCompletionChanged: { exercise, set, completed in
                        completionChanged(for: exercise, set: set, completed: completed)
                    })
            }
            .animation(.snappy, value: restTimer.isRunning)
            // **Leaving the session ends the rest.** The clock and the three
            // alerts it arms belong to this screen — the bar, the ±15 and the
            // skip are all on it — so a rest left running after the screen
            // closes is an alarm the lifter has no way to reach: it fires
            // minutes later against a session he already left, with nothing on
            // screen tying the sound to anything. On disappearing rather than on
            // the X, because there is one way out today and there is no reason
            // for the next one to have to remember this.
            .onDisappear { restTimer.stop() }
            .alert("Couldn't Save", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            // Rest is prescribed per exercise and per group, so it is edited
            // per exercise and per group: this sheet is opened from the menu on
            // the card it belongs to, whichever kind of card that is.
            .sheet(item: $restEditing) { target in
                ExerciseRestSheet(
                    exerciseName: target.name,
                    prescribedSeconds: target.prescribedSeconds,
                    rest: restPreferences.rest(for: target.key),
                    isClockOn: restPreferences.isClockOn,
                    onChange: { restPreferences.setRest($0, for: target.key) },
                    onClockSwitched: { log.clockSwitched($0) }
                )
                // The grabber, as on every other sheet. This one had a Done
                // button instead — the same chrome that was taken off the other
                // three, left on the one nobody had opened since.
                .presentationDragIndicator(.visible)
            }
            // What he wants to remember about performing it: his words, kept
            // apart from the coach's and sent on to him.
            .sheet(item: $noteExercise) { exercise in
                LifterNoteSheet(
                    exerciseName: exercise.displayName, note: exercise.lifterNote
                ) { note in
                    write {
                        exercise.lifterNote = note
                        try context.saveOrThrow()
                    }
                }
            }
            // The same screen the exercise row pushes elsewhere in the app —
            // what the movement is and what has been lifted on it are one
            // exercise, and were never worth two destinations.
            .sheet(item: $infoExercise) { exercise in
                NavigationStack {
                    ExerciseDetailView(
                        exerciseID: exercise.exerciseID,
                        displayName: exercise.displayName,
                        unit: profile.displayUnit
                    )
                }
                // The grabber, as on the block and account sheets. This one had
                // a Done button, so the app dismissed two of its sheets by
                // swipe and one by tap — three sheets, two vocabularies. The
                // platform does the dismissing either way; the button was chrome
                // for a behaviour that already exists.
                .presentationDragIndicator(.visible)
            }
        .onAppear { write(log.seedIfNeeded) }
        }
    }

    // MARK: - One card per entry

    /// An exercise performed on its own.
    private func section(for exercise: PlannedExercise) -> some View {
        Section { card(for: exercise, in: nil) }
    }

    /// A group, drawn as its movements are drawn — each with the header and the
    /// set table an ungrouped exercise gets, and each on its own panel, which is
    /// what Jon asked for. What says they are one thing is the rule down their
    /// edge and the word above their names; an earlier version instead had them
    /// share a panel with no gap, on the reasoning that two things without the
    /// gap everything else has must be one, and rendered that read as three
    /// separate exercises rather than as a pair. A signal has to be present, not
    /// withheld.
    ///
    /// That is the whole of the notation: no "Superset A", no A1/A2, no legend
    /// decoding symbols the layout had invented, and no round labels restating a
    /// set number. Rest still runs when the round closes, which is what a
    /// superset actually is.
    private func section(for group: ExerciseGroup) -> some View {
        Section {
            ForEach(group.members) { member in card(for: member, in: group) }
        }
    }

    /// One movement's card: its name, its prescription and its sets.
    ///
    /// **One function, because a grouped movement and an ungrouped one are the
    /// same card.** They were two, differing in a `paired` flag, which rest the
    /// menu edits and what a tick means — and they drifted: a completed-row
    /// background was deleted from the exercise table and left on the group's,
    /// which is a defect that cannot happen to a card there is only one of.
    ///
    /// `group` is what the movement is performed inside, or `nil` when it is
    /// performed on its own. Everything that differs between the two reads off
    /// it and nothing else.
    private func card(for exercise: PlannedExercise, in group: ExerciseGroup?) -> some View {
        let paired = group != nil
        // **One panel, one row.** The header and every set are stacked inside a
        // single list row, so the panel is one object the way a session card on
        // the block page is: one fill, one hairline, one radius, one shadow.
        // Drawn as a row each they could not be lifted at all — a `List` gives
        // every row its own layer, and a blur cast by an interior one lands on
        // its neighbours rather than behind them.
        return VStack(spacing: 0) {
            // The name sits on the panel rather than above it, so an exercise is
            // one object — its title, its prescription and its sets — instead of
            // a label floating over a table that happens to be beneath it.
            ExerciseHeaderView(
                exercise: exercise,
                unit: profile.displayUnit,
                onShowInfo: { infoExercise = exercise },
                // Rest is prescribed per exercise and per group, so the menu
                // edits whichever this movement is trained under.
                onEditRest: {
                    restEditing = group.map(RestTarget.init(group:))
                        ?? RestTarget(exercise: exercise)
                },
                onAddSet: { write { try log.addSet(to: exercise, warmup: false) } },
                onAddWarmup: { write { try log.addSet(to: exercise, warmup: true) } },
                onWriteNote: { noteExercise = exercise },
                isLocked: isLogged,
                paired: paired
            )
            .padding(.horizontal, PanelMetrics.edge)

            ExerciseLogSection(
                exercise: exercise,
                profile: profile,
                plans: plans,
                onCompletionChanged: { exercise, set, completed in
                    completionChanged(for: exercise, set: set, completed: completed, in: group)
                    showNext(after: set, of: exercise, in: group, ticked: completed)
                },
                paired: paired,
                isLocked: isLogged
            )
        }
        // The row is inset to the panel's own edges; everything inside it is
        // padded from there. Handing the row no insets at all put the content
        // outside the painted panel entirely.
        .panelRow(
            insets: EdgeInsets(
                top: 0, leading: PanelMetrics.inset, bottom: 0, trailing: PanelMetrics.inset),
            paired: paired, isRecorded: exercise.isFullyLogged)
        .listRowSeparator(.hidden)
    }

    /// Records a tick and starts whatever rest follows it.
    ///
    /// **One path, whether the tick came from the table or from the rest
    /// sheet.** A set logged in one place and the same set logged in the other
    /// must mean the same thing — including which clock starts, which is the one
    /// behavioural difference a group makes.
    private func completionChanged(
        for exercise: PlannedExercise, set: LoggedSet, completed: Bool,
        in group: ExerciseGroup? = nil
    ) {
        let group = group ?? day.entries.compactMap { $0.groupContaining(exercise) }.first
        if let group {
            write { try log.roundCompletionChanged(group, completed: completed) }
        } else {
            write { try log.completionChanged(for: exercise, isCompleted: completed) }
        }
    }

    /// Brings the next set of a group into view when one is ticked.
    ///
    /// **Only inside a group, and only on the way in.** A superset is trained
    /// across its movements and drawn down them — each has its own panel — so
    /// the next thing to do is on a panel the lifter cannot see, two rows past
    /// the bottom of the one he just tapped. Ticking is the moment he is about
    /// to move, so it is the moment worth answering.
    ///
    /// Taking a set back scrolls nowhere: he is correcting the record, not
    /// asking what is next.
    ///
    /// **It decides nothing.** The order comes from the grouping the plan
    /// prescribed — `ExerciseGroup.setAfter` — and a group with nothing waiting
    /// leaves him where he is.
    private func showNext(
        after set: LoggedSet, of member: PlannedExercise,
        in group: ExerciseGroup?, ticked: Bool
    ) {
        // An ungrouped exercise has its next set on the row below, already on
        // screen and already under his thumb.
        guard let group, ticked, let next = group.setAfter(set, of: member) else { return }
        withAnimation(.snappy) { scrollTarget = next.persistentModelID }
    }

    // MARK: - Doing

    /// Everything this screen does rather than draws. Built per redraw from what
    /// the view already holds, so there is no second copy of the session's state
    /// to keep in step with the first.
    private var log: SessionLog {
        SessionLog(
            day: day, context: context, restTimer: restTimer,
            restPreferences: restPreferences)
    }

    /// Runs a write and sends the record back out to the coach.
    ///
    /// **Finishing is the moment the snapshot goes stale.** Until this, the
    /// only thing that wrote it was the app being backgrounded, so a lifter who
    /// trained four sessions without ever leaving the app left Claude reading a
    /// document that knew about none of them — which is exactly the shape of
    /// the report that the snapshot held four sessions where the block
    /// prescribed nine. Unfinishing sends it too: taking a session back is a
    /// change to the record like any other, and a coach reading a session that
    /// was withdrawn is wrong in the same way.
    ///
    /// Only finishing, not every tick. A snapshot is the whole store
    /// serialized and written to iCloud, and doing that between sets would
    /// spend the lifter's battery to tell the coach something he is not
    /// reading yet. A failure is held by the outbox and shown the next time the
    /// app opens, exactly as a background export's is.
    private func writeAndShare(_ change: () throws -> Void) {
        write(change)
        guard errorMessage == nil, let snapshotOutbox else { return }
        Task { await snapshotOutbox.exportSnapshot() }
    }

    /// Runs a write and shows the lifter when it fails, rather than discarding
    /// the error. With CloudKit sync a save conflict is expected, not
    /// exceptional.
    private func write(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = (error as? PersistenceError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
