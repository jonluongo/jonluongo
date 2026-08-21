import SwiftUI
import SwiftData
import LiftingKit

/// The guided workout, spreadsheet-style: every exercise in one scroll, each with
/// an editable table of sets (set · previous · weight · reps · ✓). Checking a set
/// off starts the rest/pace timer, which floats in a bar at the bottom.
struct ActiveWorkoutView: View {
    let session: Session

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.exerciseCatalog) private var catalog
    @Environment(RestTimerModel.self) private var restTimer
    /// The user's own clock: whether it runs at all, and how long on each
    /// exercise. Not the prescription, and not in the store.
    @Environment(RestPreferences.self) private var restPreferences
    /// The outbox the finished session is sent through. Optional so a preview
    /// need not supply one; the app always does.
    @Environment(SnapshotOutbox.self) private var snapshotOutbox: SnapshotOutbox?
    /// Every performance there has ever been, for the one question a row asks
    /// that reaches outside this session: what he did on this movement last
    /// time.
    @Query(sort: \PerformedExercise.occurredAt) private var performances: [PerformedExercise]

    /// The clock being edited — an exercise's, or a group's — and the exercise
    /// being read about.
    @State private var restEditing: RestTarget?
    @State private var infoExercise: PlannedExercise?
    /// The exercise whose own note the user is writing.
    @State private var noteExercise: PlannedExercise?
    /// Whether the rest clock has been opened to its full size.
    @State private var showingRest = false
    /// The set to bring into view, set when a group's round moves on.
    @State private var scrollTarget: PersistentIdentifier?
    @State private var errorMessage: String?

    private var exercises: [PlannedExercise] { session.orderedExercises }

    /// The rows of this session, in the order they are trained, grouped by the
    /// movement they belong to.
    private var slotsByExercise: [PersistentIdentifier: [TrainingSlot]] {
        Dictionary(grouping: SessionOrder.trainingOrder(of: session)) {
            $0.exercise.persistentModelID
        }
    }

    /// The most recent performance of each movement *before this session*, which
    /// is what a blank load field falls back to.
    private var previous: [ExerciseID: SnapshotPerformedExercise] {
        var latest: [ExerciseID: PerformedExercise] = [:]
        for performed in performances where performed.session !== session {
            latest[performed.exerciseID] = performed
        }
        return latest.mapValues(PerformanceHistory.value(of:))
    }

    /// The session in the order it is trained: an exercise, or a group of them
    /// performed as rounds. The grouping was prescribed; nothing here makes one.
    private var entries: [SessionEntry] { SessionGrouping.entries(of: exercises) }

    /// Whether this session has been marked done. Not derived from how much of
    /// it is filled in: a user who stops at three sets of four has finished,
    /// and one resting between sets has not, and nothing in the record can tell
    /// those apart. Only he can, which is what the button is for.
    private var isLogged: Bool { session.finishedAt != nil }

    /// How many prescribed rows are not yet in the record. It decides nothing —
    /// finishing a session with sets left is entirely allowed, and often correct.
    private var unrecordedSetCount: Int {
        SessionOrder.trainingOrder(of: session).count { !$0.isDone }
    }

    /// What has been performed of one movement today, or `nil` before anything
    /// has. It is where the user's own note lives.
    private func performed(for exercise: PlannedExercise) -> PerformedExercise? {
        (session.performedExercises ?? []).first { $0.planned === exercise }
    }

    /// Whether every prescribed row of a movement is in the record, which is
    /// what tints its panel.
    private func isFullyRecorded(_ exercise: PlannedExercise) -> Bool {
        let slots = slotsByExercise[exercise.persistentModelID] ?? []
        return !slots.isEmpty && slots.allSatisfy(\.isDone)
    }

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
                    // Past the last set, which is where a user who has
                    // finished arrives. It used to be top right, where it was
                    // pressed as a way out of the screen.
                    SessionFinishSection(
                        isLogged: isLogged, unloggedSetCount: unrecordedSetCount,
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
            // screen used to waste — but the name is on the card the user
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
                CloseToolbarItem("Close workout") { dismiss() }
                // How long he has been training, counting from the first ticked
                // set. It lived in the header of a screen that no longer exists,
                // and went with it — another thing the restructure dropped
                // rather than decided.
                // The title's place, because it is the bar's own line. As a
                // leading item it was given a small fixed capsule and truncated
                // to "1…", which is a clock saying nothing.
                ToolbarItem(placement: .principal) {
                    if let startedAt = session.startedAt,
                        let lastLoggedAt = session.lastPerformedAt {
                        SessionClock(
                            startedAt: startedAt, lastLoggedAt: lastLoggedAt,
                            finishedAt: session.finishedAt)
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
                    session: session, previous: previous, restTimer: restTimer,
                    onRecord: { slot, load, reps, seconds, distance in
                        write {
                            try log.record(
                                slot, load: load, reps: reps,
                                durationSeconds: seconds, distance: distance)
                        }
                    },
                    onTakeBack: { slot in write { try log.takeBack(slot) } })
            }
            .animation(.snappy, value: restTimer.isRunning)
            // **Leaving the session ends the rest.** The clock and the three
            // alerts it arms belong to this screen — the bar, the ±15 and the
            // skip are all on it — so a rest left running after the screen
            // closes is an alarm the user has no way to reach: it fires
            // minutes later against a session he already left, with nothing on
            // screen tying the sound to anything. On disappearing rather than on
            // the X, because there is one way out today and there is no reason
            // for the next one to have to remember this.
            .onDisappear { restTimer.stop() }
            .alert("Couldn't save", isPresented: errorAlertBinding) {
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
                UserNoteSheet(
                    exerciseName: catalog.exercise(id: exercise.exerciseID)?.displayName
                        ?? exercise.exerciseID.rawValue,
                    note: performed(for: exercise)?.userNote
                ) { note in
                    write { try log.writeNote(note, for: exercise) }
                }
            }
            // The same screen the exercise row pushes elsewhere in the app —
            // what the movement is and what has been lifted on it are one
            // exercise, and were never worth two destinations.
            .sheet(item: $infoExercise) { exercise in
                NavigationStack {
                    ExerciseDetailView(
                        exerciseID: exercise.exerciseID,
                        displayName: catalog.exercise(id: exercise.exerciseID)?.displayName
                            ?? exercise.exerciseID.rawValue
                    )
                }
                // The grabber, as on the block and account sheets. This one had
                // a Done button, so the app dismissed two of its sheets by
                // swipe and one by tap — three sheets, two vocabularies. The
                // platform does the dismissing either way; the button was chrome
                // for a behaviour that already exists.
                .presentationDragIndicator(.visible)
            }
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
                onShowInfo: { infoExercise = exercise },
                // Rest is prescribed per exercise and per group, so the menu
                // edits whichever this movement is trained under.
                onEditRest: {
                    restEditing = group.map(RestTarget.init(group:))
                        ?? RestTarget(exercise: exercise)
                },
                onAddSet: { write { try log.addSet(to: exercise, warmup: false) } },
                onAddWarmup: { write { try log.addSet(to: exercise, warmup: true) } },
                isLocked: isLogged,
                paired: paired
            )
            .padding(.horizontal, PanelMetrics.edge)

            ExerciseLogSection(
                exercise: exercise,
                slots: slotsByExercise[exercise.persistentModelID] ?? [],
                performed: performed(for: exercise),
                previous: previous[exercise.exerciseID],
                onRecord: { slot, load, reps, seconds, distance in
                    write {
                        try log.record(
                            slot, load: load, reps: reps,
                            durationSeconds: seconds, distance: distance)
                    }
                    showNext(after: slot, in: group)
                },
                onTakeBack: { slot in write { try log.takeBack(slot) } },
                onWriteNote: { noteExercise = exercise },
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
            paired: paired, isRecorded: isFullyRecorded(exercise))
        .listRowSeparator(.hidden)
    }

    /// Brings the next set of a group into view when one is ticked.
    ///
    /// **Only inside a group, and only on the way in.** A superset is trained
    /// across its movements and drawn down them — each has its own panel — so
    /// the next thing to do is on a panel the user cannot see, two rows past
    /// the bottom of the one he just tapped. Ticking is the moment he is about
    /// to move, so it is the moment worth answering.
    ///
    /// Taking a set back scrolls nowhere: he is correcting the record, not
    /// asking what is next.
    ///
    /// **It decides nothing.** The order comes from the grouping the plan
    /// prescribed — `ExerciseGroup.setAfter` — and a group with nothing waiting
    /// leaves him where he is.
    private func showNext(after slot: TrainingSlot, in group: ExerciseGroup?) {
        // An ungrouped exercise has its next set on the row below, already on
        // screen and already under his thumb.
        guard let group, let next = group.setAfter(slot.planned, of: slot.exercise)
        else { return }
        withAnimation(.snappy) { scrollTarget = next.persistentModelID }
    }

    // MARK: - Doing

    /// Everything this screen does rather than draws. Built per redraw from what
    /// the view already holds, so there is no second copy of the session's state
    /// to keep in step with the first.
    private var log: SessionLog {
        SessionLog(
            session: session, context: context, restTimer: restTimer,
            restPreferences: restPreferences)
    }

    /// Runs a write and sends the record back out to the coach.
    ///
    /// **Finishing is the moment the snapshot goes stale.** Until this, the
    /// only thing that wrote it was the app being backgrounded, so a user who
    /// trained four sessions without ever leaving the app left Claude reading a
    /// document that knew about none of them — which is exactly the shape of
    /// the report that the snapshot held four sessions where the block
    /// prescribed nine. Unfinishing sends it too: taking a session back is a
    /// change to the record like any other, and a coach reading a session that
    /// was withdrawn is wrong in the same way.
    ///
    /// Only finishing, not every tick. A snapshot is the whole store
    /// serialized and written to iCloud, and doing that between sets would
    /// spend the user's battery to tell the coach something he is not
    /// reading yet. A failure is held by the outbox and shown the next time the
    /// app opens, exactly as a background export's is.
    private func writeAndShare(_ change: () throws -> Void) {
        write(change)
        guard errorMessage == nil, let snapshotOutbox else { return }
        Task { await snapshotOutbox.exportSnapshot() }
    }

    /// Runs a write and shows the user when it fails, rather than discarding
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
