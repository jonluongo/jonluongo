import SwiftUI
import LiftingKit

/// The section header for one exercise on the logging screen: icon, name, what
/// the plan asked for, and the menu.
///
/// **What it does.** Says which exercise the table below it logs, and states the
/// prescription in one line — the sets, what they ask for, the span of load
/// where the sets differ in it, and the effort.
///
/// **How it is used.** `ActiveWorkoutView` puts one above each exercise's
/// section. The menu holds the four things there are to do to an exercise
/// rather than to a set: read what it is, set its clock, and add a set of
/// either kind.
///
/// **The rest is not written here at all.** It led the card below as a
/// full-width tappable row above the column headers, which gave the most
/// prominent place on the card to the one thing on it nobody came to read; it
/// moved into this line, and then off the screen entirely. What it prescribes is
/// stated on Home beside the sets and the reps, before the lifter decides to
/// train; under the bar it arrives as a countdown when a set is ticked, which is
/// the form it is actually used in. A third statement of it, on the card, was
/// crowding the sets to repeat something already said and already running. The
/// menu sets the clock and names the prescription for anyone who wants the
/// figure.
///
/// **Adding a set lives here because the two ways of adding one are the same
/// kind of thing.** A warm-up was a menu item while a working set was a
/// full-width button in the middle of the table, so the same act read as two
/// different acts and one of them was a permanent fixture competing with the
/// rows it sat among. The ability itself is not in question: the app records
/// what happened, so a fifth set actually performed must be recordable even
/// though four were prescribed.
///
/// **What it depends on.** `IconCircleRow` for the shape — the plan screen's
/// day row draws the same one, and the two used to be separate code that had
/// drifted six ways — and `PrescriptionSummary` for the words. It lives beside
/// its twin rather than inside the screen that uses it, which is what makes a
/// future divergence visible.
struct ExerciseHeaderView: View {
    let exercise: PlannedExercise
    /// The lifter's display unit, carried down to the prescription.
    let unit: MassUnit
    var onShowInfo: () -> Void
    var onEditRest: () -> Void
    /// Records a set past the ones prescribed — the fifth he actually did.
    var onAddSet: () -> Void
    var onAddWarmup: () -> Void

    private var subtitle: String {
        let summary = PrescriptionSummary.text(for: exercise, unit: unit)
        guard let tempo = exercise.tempo, !tempo.isEmpty else { return summary }
        return "\(summary) · tempo \(tempo)"
    }

    var body: some View {
        IconCircleRow(
            systemImage: "dumbbell.fill",
            tint: .accentColor,
            title: exercise.displayName,
            subtitle: subtitle
        ) {
            Menu {
                Button { onShowInfo() } label: {
                    Label("About This Exercise", systemImage: "info.circle")
                }
                Button { onEditRest() } label: {
                    Label("Rest Timer", systemImage: "timer")
                }
                Button { onAddSet() } label: {
                    Label("Add Set", systemImage: "plus")
                }
                Button { onAddWarmup() } label: {
                    Label("Add Warmup Set", systemImage: "flame")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.barbellBody)
                    .foregroundStyle(.secondary)
                    .frame(width: TapTarget.minimum, height: TapTarget.minimum, alignment: .trailing)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(exercise.displayName) options")
        }
    }
}
