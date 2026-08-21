import SwiftUI
import LiftingKit

/// The section header for one exercise on the logging screen: the name, what the
/// plan asked for, and the menu.
///
/// **What it does.** Says which exercise the table below it logs, and states the
/// part of the prescription that table will not — the effort every set shares.
/// The count is the number of rows and the target is the placeholder in each of
/// them, so restating either here was the card saying the same thing twice and
/// charging the sets for the space.
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
/// though four were prescribed — which is why it is called *Add Extra Set*, at
/// the foot of the menu: it adds work the plan did not ask for.
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

    @Environment(\.exerciseCatalog) private var catalog

    let exercise: PlannedExercise
    var onShowInfo: () -> Void
    var onEditRest: () -> Void
    /// Records a set past the ones prescribed — the fifth he actually did.
    var onAddSet: () -> Void
    var onAddWarmup: () -> Void
    /// Opens the lifter's own note about performing this movement today.
    /// Whether the session has been marked finished. Adding work to a session
    /// that is over is an edit to the record, so those two items go; reading
    /// about the movement, setting the clock and writing what happened are not,
    /// and stay.
    var isLocked: Bool = false
    /// Whether this movement is performed as part of a superset, which names it
    /// above the prescription and draws the rule down the panel's edge.
    var paired: Bool = false

    /// What the table below cannot say: the effort every set shares. `nil` when
    /// it says everything, which leaves the header the name alone.
    ///
    /// **Tempo used to be the other half of this line and is not a field any
    /// more** — nothing parsed it, and two free-text boxes on one exercise
    /// invited a coin-flip about which to write in, so it folded into the
    /// coach's note.
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

    /// What the movement is called. **The catalog owns it**, keyed by
    /// `exerciseID`; the store used to keep a copy, which was a second place for
    /// a name to live and disagree from. An ID the catalog does not have cannot
    /// reach here — the importer refuses it — so the fallback is the key itself
    /// rather than a blank.
    private var name: String {
        catalog.exercise(id: exercise.exerciseID)?.displayName ?? exercise.exerciseID.rawValue
    }

    /// What the exercise asks for above its table.
    ///
    /// **Tempo used to sit here**, and it folded into the coach's note: nothing
    /// parsed it, and two free-text fields on one exercise invited a coin-flip
    /// about which to write in.
    private var subtitle: String? { PrescriptionSummary.aboveTable(for: exercise) }

    var body: some View {
        CardHeaderRow(title: name, subtitle: subtitle, eyebrow: eyebrow) {
            Menu {
                Button { onShowInfo() } label: {
                    Label("About This Exercise", systemImage: "info")
                }
                Button { onEditRest() } label: {
                    Label("Rest Timer", systemImage: "timer")
                }
                // Warm-up first, extra set last, and the extra set says
                // *extra*: "Add Set" beside "Add Warmup Set" read as though one
                // of them were the ordinary way to add a set, when both are
                // additions past what was prescribed. The one at the foot is the
                // one that adds work the plan did not ask for.
                if !isLocked {
                    Button { onAddWarmup() } label: {
                        Label("Add Warmup Set", systemImage: "flame")
                    }
                    Button { onAddSet() } label: {
                        Label("Add Extra Set", systemImage: "plus")
                    }
                }
            } label: {
                // No frame of its own. It had one, 44pt wide and aligned
                // trailing, which pinned the glyph to the right edge of its own
                // column while every check below it sat centred in a column of
                // the same width — so the two were half a column apart. The
                // header row gives the control the check column's width and
                // centres it, which is the whole reason that width is stated
                // there.
                Image(systemName: "ellipsis")
                    .font(.supersetBody)
                    // Named, not `.secondary`. A hierarchical style resolves
                    // against whatever tint is in scope, and inside a `Menu`
                    // that is the accent — so this glyph measured neutral grey
                    // in light and olive in dark, the same control in two
                    // colours. Every colour in this app is one of Style's own.
                    .foregroundStyle(Palette.muted)
                    // **Fill the frame before taking the shape from it.**
                    // `CardHeaderRow` gives this control 44 points square, but
                    // the shape was being taken from the glyph inside it — about
                    // seventeen points of ellipsis — so three quarters of the
                    // target the layout had reserved did nothing. It read as a
                    // control that only sometimes worked.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .accessibilityLabel("\(name) options")
        }
    }
}
