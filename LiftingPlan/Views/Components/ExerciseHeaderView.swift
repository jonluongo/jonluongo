import SwiftUI
import LiftingKit

/// The section header for one exercise on the logging screen: the name, what the
/// plan asked for, and the menu.
///
/// **What it does.** Says which exercise the table below it logs, and states the
/// part of the prescription that table will not — the effort every set shares,
/// and the tempo. The count is the number of rows and the target is the
/// placeholder in each of them, so restating either here was the card saying the
/// same thing twice and charging the sets for the space.
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
/// **There is no icon.** Every exercise drew the same dumbbell in the same
/// circle, so the glyph told a lifter nothing about which exercise he was
/// looking at while indenting every name by forty-eight points. A mark
/// identical everywhere it appears is decoration.
///
/// **What it depends on.** `CardHeaderRow` for the shape — a group's header
/// draws the same one, and the two used to be separate code that had drifted six
/// ways — and `PrescriptionSummary` for the words. It lives beside its twin
/// rather than inside the screen that uses it, which is what makes a future
/// divergence visible.
struct ExerciseHeaderView: View {
    let exercise: PlannedExercise
    /// The lifter's display unit, carried down to the prescription.
    let unit: MassUnit
    var onShowInfo: () -> Void
    var onEditRest: () -> Void
    /// Records a set past the ones prescribed — the fifth he actually did.
    var onAddSet: () -> Void
    var onAddWarmup: () -> Void
    /// Whether this movement is performed as part of a superset, which names it
    /// above the prescription and draws the rule down the panel's edge.
    var paired: Bool = false

    /// What the table below cannot say: the effort every set shares, and the
    /// tempo. `nil` when it says everything, which leaves the header the name
    /// alone.
    ///
    /// It used to restate the prescription in full — `3 × 10-12 · RPE 8` over
    /// three rows whose rep fields each read `10-12`. The count is the number of
    /// rows and the target is in every one of them; only the effort was not
    /// anywhere else on the card.
    /// Named where a lifter reads it, above the movement it belongs to.
    ///
    /// The word is back and the code is not. `Superset A` was a letter
    /// distinguishing a group from a B that usually does not exist, plus an
    /// `A1`/`A2` legend decoding symbols the layout had invented. This says the
    /// one thing that is true of both movements and needs no decoding, and the
    /// rule down the panel edge says which two.
    private var eyebrow: String? { paired ? "Superset" : nil }

    private var subtitle: String? {
        let parts = [
            PrescriptionSummary.aboveTable(for: exercise),
            exercise.tempo.flatMap { $0.isEmpty ? nil : "tempo \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        CardHeaderRow(title: exercise.displayName, subtitle: subtitle, eyebrow: eyebrow) {
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
