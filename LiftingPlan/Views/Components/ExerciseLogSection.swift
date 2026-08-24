import SwiftUI
import LiftingKit

/// The editable body of one exercise's section: its set table, and the two notes
/// under it.
///
/// **The table is rows and nothing else.** Adding a set was a full-width button
/// under the last row, which made an occasional act a permanent fixture of the
/// table and put it beside the rows it was not part of. It is a menu item on
/// `ExerciseHeaderView` now, next to the warm-up it always resembled.
///
/// **Rest is not in here.** It was this card's first row, a full-width line
/// above the column headers, which made the card's most prominent statement the
/// one thing nobody came to read: the sets are the subject and the rest is a
/// detail of them.
///
/// **Every per-set statement reaches the user on the row it describes.** This
/// used to draw the whole prescription again as a numbered block above the
/// table, so the sentence about set four was off the top of the screen by the
/// time he reached set four.
///
/// **The only thing this writes is the record.** The prescription is read and
/// displayed, never edited.
///
/// **What it depends on.** `TrainingSlot` for the rows, `SetRowView` for each
/// one, and one previous performance for the field a prescription may leave
/// blank. It draws a movement performed on its own and one inside a group;
/// `paired` is the only difference.
struct ExerciseLogSection: View {

    let exercise: PlannedExercise
    /// This exercise's rows, in the order they are trained.
    let slots: [TrainingSlot]
    /// What has been performed of this movement today, or `nil` before anything
    /// has. It is where the user's own note lives.
    let performed: PerformedExercise?
    /// What he did on this movement last time, for the load field a
    /// prescription may leave blank.
    let previous: SnapshotPerformedExercise?
    var onRecord: (TrainingSlot, Mass?, WorkDone) -> Void
    var onTakeBack: (TrainingSlot) -> Void
    /// Opens the sheet he writes his note in. Wired here rather than to the
    /// header's menu, so the control that writes the note sits where the note
    /// lands.
    var onWriteNote: () -> Void = {}
    /// Whether this movement is performed inside a group.
    var paired: Bool = false
    /// Whether the session has been marked finished.
    var isLocked: Bool = false

    var body: some View {
        VStack(spacing: Spacing.tight) {
            ForEach(slots) { slot in
                SetRowView(
                    slot: slot,
                    prescription: SetRowPrescription(slot: slot, previous: previous),
                    isLocked: isLocked,
                    onRecord: { load, work in onRecord(slot, load, work) },
                    onTakeBack: { onTakeBack(slot) })
                .padding(.horizontal, PanelMetrics.edge)
            }

            // At the foot rather than between the header and the table: a note
            // above the rows moved the first row down, so two exercises in one
            // session had their first row in different places. At the foot it is
            // additive — everything above it is where it always is.
            if let coachNote = exercise.coachNote, !coachNote.isEmpty {
                note(coachNote, isLifters: false)
            }
            // **His own, under the coach's, and always present.** The two say
            // different things — the coach's is detail on the work in front of
            // him, this is what happened while doing it — so they are two lines
            // rather than one.
            //
            // Writing one was an item in the header's overflow menu: three taps
            // from a thought he had mid-set, behind a control that gave no sign
            // it held anything about notes. The line he reads his note on is the
            // line he writes it from, and when he has not written one it says so
            // rather than being absent.
            userNote
        }
    }

    /// His note, or the invitation to write one — the same line either way.
    ///
    /// A finished session still opens the sheet: what he wrote about a movement
    /// is his, and finishing is a statement about the training rather than about
    /// his account of it.
    @ViewBuilder
    private var userNote: some View {
        let mine = performed?.userNote
        Button(action: onWriteNote) {
            note(mine?.isEmpty == false ? mine ?? "" : "Add a note",
                 isLifters: true,
                 isPrompt: mine?.isEmpty != false)
        }
        .buttonStyle(.plain)
    }

    /// A line at the foot of the panel, marked with who wrote it.
    ///
    /// **The coach's is the darker one, and it used to be the other way round.**
    /// The reasoning behind the old order was that the note he typed should read
    /// like him — but weight on a screen is not authorship, it is what to read
    /// first. The coach's note is an instruction about the work in front of him;
    /// his own is a record of work already done. The one he still has to act on
    /// is the one that carries the ink.
    ///
    /// **The glyph says whose, the weight says which to read.** Colour alone was
    /// doing both jobs and doing neither clearly: two grey-ish lines at the foot
    /// of a panel, and no way to tell at a glance which was the prescription.
    ///
    /// **Said to him, or written by him — and both marks are outlines at the
    /// same weight.** A filled bubble against a hairline pencil was two line
    /// weights in one pair, which read as an oversight rather than a
    /// distinction.
    ///
    /// **Four pairs were rendered before this one, and the size decided it.**
    /// These marks draw at subheadline, so a glyph that reads on a symbol sheet
    /// can be a smudge here:
    ///
    /// - `bubble.left` / `bubble.right` — mirroring one glyph is the cleanest
    ///   single axis available, and every messaging app already teaches which
    ///   side is yours. But the tail carrying the entire difference is a couple
    ///   of points wide, so rendered they were the same mark twice. A variation
    ///   the eye cannot resolve distinguishes nothing.
    /// - `clipboard` — thin, and a rounded rectangle standing beside
    ///   `square.and.pencil`, so the pair shared a silhouette.
    /// - `person.bust` — collapses to a chess pawn at this size.
    /// - `text.bubble` — legible, but says *a message* rather than *from him*.
    ///
    /// `person.bubble` keeps a person in it at 14 points, which is the one thing
    /// the mark has to say. There is no whistle in SF Symbols, and no
    /// third-party set is coming: see the icon rules in CLAUDE.md.
    ///
    /// **A prompt is the same line, not a different one.** *Add a note* draws
    /// exactly where his note will draw, in the same ink and behind the same
    /// mark, so writing one changes the words and moves nothing.
    private func note(_ text: String, isLifters: Bool, isPrompt: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
            Image(systemName: isLifters ? "square.and.pencil" : "person.bubble")
                .imageScale(.small)
                .frame(width: Self.noteGlyphWidth, alignment: .center)
                .accessibilityHidden(true)
            Text(text)
        }
        // **The whole row centres, not the text inside it.** Centring the label
        // within the space left over after the glyph pushes it right by the
        // glyph's width — near the middle and never on it.
        .frame(maxWidth: .infinity, alignment: .center)
        .font(.supersetSupport)
        .foregroundStyle(isLifters ? Palette.muted : Palette.ink)
        // **Centred, like everything else at the foot of a panel.** The notes
        // were flush left under a table whose columns are centred, so the last
        // line of every exercise hung off the left edge on its own.
        .multilineTextAlignment(.center)
        .padding(.horizontal, PanelMetrics.edge)
        .padding(.top, Spacing.standard)
        // The whole line is the target, not the words: a tap anywhere along it
        // opens the sheet, which is what makes an empty prompt reachable.
        .frame(minHeight: isLifters ? TapTarget.minimum : 0, alignment: .leading)
        .contentShape(.rect)
        // The glyph is decoration to a reader who cannot see it; the sentence
        // has to say whose note this is, since that is what the mark conveys.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isLifters
                ? (isPrompt ? "Add your note" : "Your note. \(text)")
                : "Coach's note. \(text)")
        .accessibilityAddTraits(isLifters ? .isButton : [])
    }

    /// Fixed so both notes read as the same shape — a person-in-a-bubble and a
    /// pencil-in-a-square are not the same width, and two centred rows whose
    /// glyphs sit at different offsets look accidental.
    private static let noteGlyphWidth: CGFloat = 16
}
