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
/// **The rest is a clause in this line, not a row of its own.** It used to lead
/// the card below — a full-width tappable line above the column headers — which
/// gave the most prominent place on the card to the one thing on it nobody came
/// to read. It reads here beside the sets and the effort, and the clock is set
/// from the menu, which is where everything else done to a whole exercise
/// already is. That costs a tap on a setting changed rarely and buys a row back
/// on every exercise of every session.
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

    /// The lifter's own clock, which is not part of the plan and not in the
    /// store. Read only to say what will actually run.
    @Environment(RestPreferences.self) private var restPreferences

    private var subtitle: String {
        var parts = [PrescriptionSummary.text(for: exercise, unit: unit)]
        if let tempo = exercise.tempo, !tempo.isEmpty {
            parts.append("tempo \(tempo)")
        }
        // Absent when the plan prescribed no rest and the lifter has asked for
        // none. Nothing invites him to fill that gap in: the menu is where a
        // timer on an unprescribed exercise is asked for.
        if let rest = RestPrescription.line(
            prescribed: exercise.restSeconds,
            lifter: restPreferences.rest(for: exercise.exerciseID),
            timersEnabled: restPreferences.timersEnabled
        ) {
            parts.append(rest.lowercasedFirst)
        }
        return parts.joined(separator: " · ")
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
