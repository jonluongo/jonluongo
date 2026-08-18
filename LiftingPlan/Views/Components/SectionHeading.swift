import SwiftUI

/// The name of a section, drawn the way this app draws headings.
///
/// **What it does.** Replaces the small grey capitals a `List` puts above a
/// section — which say "column of a table" — with the Heading role and the
/// spacing every other heading in the app uses, so a section on the Blocks tab
/// and an exercise on the logging screen read as the same kind of thing.
///
/// **How it is used.** `Section { ... } header: { SectionHeading("Weeks") }`.
///
/// **What it depends on.** `Spacing`, `Palette` and the type ramp.
struct SectionHeading: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.barbellHeading)
            .foregroundStyle(Palette.ink)
            .textCase(nil)
            .padding(.top, Spacing.standard)
            .padding(.bottom, Spacing.snug)
    }
}
