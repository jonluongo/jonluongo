import SwiftUI

/// The name of a section, drawn the way this app draws headings.
///
/// **What it does.** Replaces the small grey capitals a `List` puts above a
/// section — which say "column of a table" — with the Heading role and the
/// spacing every other heading in the app uses, so a section on the Blocks tab
/// and an exercise on the logging screen read as the same kind of thing.
///
/// **How it is used.** As the *first row* of a section, not as its header:
/// `Section { SectionHeading("Weeks"); ... }`. A plain `List` pins a header to
/// the top of the screen and scrolls the rows under it, so a week's name sat
/// frozen over the days of another week — the heading claiming to describe what
/// was passing beneath it. A row scrolls with what it names. Everything a row
/// needs to sit flush with the panels below it is applied here, so no caller
/// restates it.
///
/// **What it depends on.** `Spacing`, `Palette` and the type ramp.
struct SectionHeading: View {

    let text: String
    /// Whether what it heads is not yet due. Drawn quieter, never differently:
    /// it is the same heading, further back.
    var recessed: Bool = false

    init(_ text: String, recessed: Bool = false) {
        self.text = text
        self.recessed = recessed
    }

    var body: some View {
        Text(text)
            .font(.supersetHeading)
            .foregroundStyle(recessed ? Palette.muted : Palette.ink)
            .textCase(nil)
            .padding(.top, Spacing.standard)
            .padding(.bottom, Spacing.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The same inset as a panel, so a name and the edge of what it names
            // share a line.
            .padding(.horizontal, PanelMetrics.inset)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
