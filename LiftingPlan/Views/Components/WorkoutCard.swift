import SwiftUI
import LiftingKit

/// One prescribed session on Home: what it is, everything it asks for, and the
/// tap that starts it.
///
/// **What it does.** Draws the whole session — its name, its shape, and every
/// exercise with what the plan asks of it — inside a single panel that is itself
/// the control. Tapping anywhere on it opens the logging screen.
///
/// **The card is the button.** There was a `Start Workout` button pinned under
/// it, which meant the thing filling the screen was inert and the thing that
/// acted was a bar at the bottom. One object that does one thing is fewer moving
/// parts and a much larger target for a hand that is already holding a phone in
/// a gym.
///
/// **Nothing inside it is separately tappable.** The exercise rows used to push
/// that exercise's record. An object cannot have two tap meanings, and the outer
/// one — start this session — is what Home is for; the record is still reached
/// from inside a session through an exercise's menu, and from the Blocks tab.
///
/// **Every card is the same height.** It fills the space between the header and
/// the tab bar rather than sizing to its contents, so swiping between a
/// six-exercise session and a three-exercise one does not resize the thing under
/// the thumb. A session too long to fit scrolls inside the card; the tap still
/// works, because a tap is not a drag.
///
/// **What it depends on.** `WorkoutDay` from Store, `PrescribedExerciseRow` and
/// `PrescribedGroupSummary` for the contents, `TodayPhrasing` for the words, and
/// the panel tokens. It writes nothing and decides nothing: the session it draws
/// was prescribed, and whether to start it is a tap.
struct WorkoutCard: View {

    let session: WorkoutDay
    /// The lifter's display unit, so a prescribed load reads in the unit he
    /// reads everything else in.
    let unit: MassUnit
    var onStart: () -> Void

    private var shape: String? {
        TodayPhrasing.sessionShape(
            exercises: session.orderedExercises.count,
            durationMinutes: session.durationMinutes)
    }

    /// Said only when the record has something to say — a session already under
    /// way, or one already logged. A session nobody has touched says nothing,
    /// which is the ordinary case.
    private var progress: String? {
        TodayPhrasing.progressNote(for: TodayInPlan.progress(of: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heading
                ForEach(Array(session.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Palette.rule)
                            .frame(height: Palette.hairline)
                    }
                    row(for: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.panel, in: .rect(cornerRadius: Radius.panel))
        .contentShape(.rect)
        // A tap rather than a `Button` wrapping the whole thing: a button would
        // take the drag as well, and the contents have to be able to scroll when
        // a session runs past the height of the card.
        .onTapGesture(perform: onStart)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Start \(TodayPhrasing.sessionTitle(focus: session.focus, weekday: session.weekday))")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(TodayPhrasing.sessionTitle(focus: session.focus, weekday: session.weekday))
                .font(.barbellHeading)
                .foregroundStyle(Palette.ink)
            HStack(spacing: Spacing.snug) {
                if let shape {
                    Text(shape)
                        .font(.barbellSupport)
                        .foregroundStyle(Palette.muted)
                }
                if let progress {
                    Text(progress)
                        .font(.barbellSupport)
                        .foregroundStyle(Palette.recorded)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.standard)
        .padding(.top, Spacing.standard)
        .padding(.bottom, Spacing.snug)
    }

    @ViewBuilder
    private func row(for entry: SessionEntry) -> some View {
        Group {
            switch entry {
            case .exercise(let exercise):
                PrescribedExerciseRow(exercise: exercise, unit: unit)
            case .group(let group):
                PrescribedGroupSummary(group: group, unit: unit)
            }
        }
        .padding(.horizontal, Spacing.standard)
    }
}
