import SwiftUI

/// A title, a line under it, and an optional control on the right.
///
/// **What it does.** Draws the header above a card on the logging screen — the
/// exercise's, and the group's. It began as a row with a glyph in a tinted
/// circle and lost the circle, because the icon carried no information: every
/// exercise drew the same dumbbell and every group the same rotate arrows, so
/// the glyph distinguished nothing from anything while indenting every title by
/// forty-eight points. A mark that is identical everywhere it appears is
/// decoration.
///
/// **How it is used.** Give it the two lines of text, and a control as
/// `trailing` when the header has one — it gets a 44pt target whatever glyph it
/// draws, centred on the column of marks below so the two share a centre.
///
/// **What it depends on.** `Spacing`, `TapTarget`, and the type ramp. It reads
/// no model — callers hand it strings.
struct CardHeaderRow<Trailing: View>: View {

    let title: String
    /// The line under the title, or `nil` when there is nothing to say. Never an
    /// empty string standing in for one.
    let subtitle: String?
    /// A short label above the title, in the accent, with the bolt that marks
    /// it. `nil` on everything that is not part of a superset, which is most
    /// things.
    var eyebrow: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        // The eyebrow sits above the row rather than inside it. Kept in the
        // same stack as the title, it made the title one of two lines the
        // control centred between, so the `⋯` on a paired exercise floated
        // between the label and the name while the same control on every other
        // card sat squarely on the title. The control's position must not
        // depend on whether the movement happens to be in a group.
        VStack(alignment: .leading, spacing: Spacing.snug) {
            if let eyebrow {
                // An `HStack`, not a `Label`: `tracking` letter-spaces the gap
                // between a label's glyph and its text as well as the text
                // itself, which pushed the bolt away from the word it marks.
                HStack(spacing: Spacing.tight) {
                    Image(systemName: "bolt.fill")
                    Text(eyebrow)
                        .tracking(Font.labelTracking)
                        .textCase(.uppercase)
                }
                .font(.supersetLabel)
                .foregroundStyle(Palette.accent)
            }
            HStack(spacing: Spacing.standard) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(title)
                        .font(.supersetHeading)
                        .foregroundStyle(Palette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.supersetSupport)
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer()
                // A row with no control claims no room for one: an empty
                // trailing view given a 44pt frame would indent every row that
                // has nothing on its right.
                if Trailing.self != EmptyView.self {
                    // The same width as the column of marks below it, so the two
                    // share a centre. Sizing itself, the control sat a few points
                    // outboard of every check in the table — close enough to look
                    // like a mistake and not close enough to look deliberate.
                    trailing()
                        .frame(
                            width: SetTableMetrics.checkColumnWidth,
                            height: TapTarget.minimum)
                }
            }
        }
        // Even, because the header sits *inside* the panel now. It used to sit
        // above one, where extra room on top separated it from the panel it had
        // finished with — and carrying that inside made the panel's top airy
        // while its last set row closed almost against the edge. The gap between
        // panels does the separating; this only spaces the title from its own
        // table.
        .padding(.vertical, Spacing.snug)
    }
}

extension CardHeaderRow where Trailing == EmptyView {

    /// The row without a control on the right.
    init(title: String, subtitle: String?, eyebrow: String? = nil) {
        self.init(title: title, subtitle: subtitle, eyebrow: eyebrow) { EmptyView() }
    }
}
