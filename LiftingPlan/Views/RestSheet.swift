import SwiftUI
import SwiftData
import LiftingKit

/// The rest clock, big enough to read from the floor, with the next set under
/// it.
///
/// **What it does.** Shows one thing at a time: how long is left, and the single
/// row he is about to do. Ticking that row logs it and the sheet moves to the
/// next one — so a lifter between sets can work through a session without
/// finding his place in a table.
///
/// **Why a sheet and not a screen.** It is a state he is in for ninety seconds,
/// not a place he goes. It slides over the session he is already looking at, it
/// keeps its context — the table is still behind it — and it is dismissed by
/// pulling it down rather than by a button.
///
/// **The countdown is the largest thing on it**, because that is the figure he
/// is waiting on. Everything else is one row: the movement's name, the load and
/// the target, and the check.
///
/// **It shows the next set, not the one he just did.** Rest exists because
/// something comes next, so the useful row is the next one — and when nothing
/// does, the sheet says so rather than showing an empty table.
///
/// **What it depends on.** `RestTimerModel` for the clock, `SessionOrder` for
/// what is next, `SetRowView` for the row — the same one the table draws, so a
/// set logged here and a set logged there cannot come to mean different things —
/// and `SessionLog` for the write.
struct RestSheet: View {

    let day: WorkoutDay
    let profile: UserProfile
    let plans: [TrainingPlan]
    var restTimer: RestTimerModel
    /// Called with the set that was ticked, so the session can start the rest
    /// that follows it exactly as the table would.
    var onCompletionChanged: (PlannedExercise, LoggedSet, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    /// The row being drawn, once it has stopped being the next one. See
    /// `shown`.
    @State private var heldID: PersistentIdentifier?

    /// The row he is about to do, or `nil` when every row is ticked.
    private var next: TrainingSlot? { SessionOrder.next(in: day) }

    /// The row on screen: the one he just ticked while the tick is still being
    /// shown, and the next one after that.
    ///
    /// **A tick has to land before the sheet moves on.** Advancing the moment
    /// the box was ticked meant the box he pressed was gone before it filled —
    /// Jon: *"I still want to see the check before we move on it should register
    /// as completed."* The write itself is immediate; only the row's departure
    /// waits, so the record and the clock are never held up by an animation.
    private var shown: TrainingSlot? {
        guard let heldID,
            let held = SessionOrder.trainingOrder(of: day).first(where: { $0.id == heldID })
        else { return next }
        return held
    }

    var body: some View {
        VStack(spacing: Spacing.major) {
            clock
            controls
            Spacer(minLength: 0)
            if let shown {
                row(shown)
                    // The row is identified by the set it draws, so ticking one
                    // replaces the view rather than editing it in place — which
                    // is what makes the change visible at all. Without this the
                    // same row simply lost its tick and gained a new number, and
                    // Jon read that as nothing having happened: *"it just looks
                    // like its staying on the same set."*
                    .id(shown.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                // Every row is ticked, so the only thing left to say is that
                // the clock is running for nothing in particular.
                Text("Nothing left to do.")
                    .font(.supersetBody)
                    .foregroundStyle(Palette.muted)
            }
        }
        // Clear of the grabber: the ring's twelve o'clock is exactly where the
        // sheet draws it, and the two nearly touching read as one broken shape.
        // The ring gives the room back — a sheet of a fixed height has only so
        // much, and the row at the foot is not what should pay for it.
        .padding(.top, Spacing.major * 2 + Spacing.section)
        .padding(.bottom, Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.surface)
        // Half the screen: enough for a ring read at arm's length and one row,
        // and no more — the session it slid over is still the thing he is doing.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        // The sheet exists because a clock is running. When it stops there is
        // nothing left on it but a row he can log from the table behind, so it
        // gets out of the way rather than becoming a second place to log.
        .onChange(of: restTimer.isRunning) { _, isRunning in
            if !isRunning { dismiss() }
        }
    }

    /// The figure he is waiting on, in the same ring the bar draws.
    ///
    /// **The ring says how long and nothing else.** It carried the name of the
    /// movement the rest belongs to as well, which is the movement he has just
    /// finished — and the row below names the one he is about to do. Rendered,
    /// the two were the same words twice on the same sheet, and the wrong one
    /// was the larger.
    ///
    /// It was drawn here by hand for one build, which is how the bar came to
    /// fill while this drained: the same clock, two behaviours. `TimerRing`
    /// takes a size, a stroke and a type role, so there is one ring.
    private var clock: some View {
        TimerRing(
            progress: restTimer.progress,
            timeText: restTimer.formattedRemaining,
            isRunning: restTimer.isRunning,
            size: Self.ringSize,
            lineWidth: Self.ringWidth,
            showsLabel: false,
            font: .supersetClock)
    }

    /// The same three things the bar does, at the size of a thing pressed with
    /// a thumb between sets. The sheet must not be able to do less than the bar
    /// it was opened from, or leaving it becomes the way to reach them.
    private var controls: some View {
        HStack(spacing: Spacing.section) {
            Button("−15") { restTimer.addTime(-15) }
            Button("+15") { restTimer.addTime(15) }
            Button {
                restTimer.skip()
            } label: {
                Label("Skip rest", systemImage: "forward.end.fill")
                    .labelStyle(.iconOnly)
            }
            .tint(Palette.accent)
            .foregroundStyle(Palette.onAccent)
        }
        .font(.supersetBody)
        .fontWeight(.semibold)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Palette.rule)
        .foregroundStyle(Palette.ink)
    }

    /// The next set, drawn by the same row the table draws.
    private func row(_ slot: TrainingSlot) -> some View {
        let reading = SetRowPrescription(
            exercise: slot.exercise, plans: plans, unit: profile.displayUnit)
        let prescribed = reading.prescription(
            forWorkingNumber: slot.workingNumber, isWarmup: slot.set.isWarmup)
        return VStack(alignment: .leading, spacing: Spacing.standard) {
            Text(slot.exercise.displayName)
                .font(.supersetTitle)
                .foregroundStyle(Palette.ink)
            SetRowView(
                set: slot.set,
                identity: slot.identity,
                repTargetText: WorkPrescription.targetFigure(
                    for: prescribed?.repRange,
                    measure: WorkPrescription.measure(for: prescribed, in: slot.exercise)),
                loadTargetText: reading.loadTarget(prescribed),
                prescriptionDetail: PrescriptionSummary.detail(
                    for: prescribed, in: slot.exercise),
                measure: WorkPrescription.measure(for: prescribed, in: slot.exercise),
                unit: profile.displayUnit,
                // Animated from here rather than by the caller: the set the
                // sheet is showing changes as a result of this write, and the
                // slide out and in is the whole of the answer to *did that
                // land?* The rest of the session's writes are the table's, and
                // a table does not move.
                onCompletionChanged: { completed in
                    onCompletionChanged(slot.exercise, slot.set, completed)
                    advance(after: slot, ticked: completed)
                }
            )
        }
        .padding(PanelMetrics.edge)
        .panelSurface()
        .padding(.horizontal, PanelMetrics.inset)
    }

    /// Holds the ticked row on screen long enough to see the mark fill, then
    /// slides it away and brings the next one in.
    ///
    /// Untick and nothing moves: he is correcting the row he is looking at, and
    /// taking it off the screen mid-correction is the same fault in reverse.
    private func advance(after slot: TrainingSlot, ticked: Bool) {
        guard ticked else { return }
        heldID = slot.id
        Task {
            try? await Task.sleep(for: .seconds(Self.markLingers))
            withAnimation(.snappy) { heldID = nil }
        }
    }

    /// How long the ticked row stays before it leaves. Long enough that the mark
    /// filling is something he saw happen, short enough that the sheet is not
    /// waiting on him between sets.
    private static let markLingers = 0.45

    /// Read at arm's length with a phone on the floor, which is what makes this
    /// worth a sheet of its own.
    private static let ringSize: CGFloat = 172
    private static let ringWidth: CGFloat = 8
}
