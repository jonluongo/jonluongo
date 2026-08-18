import SwiftUI

/// A screen's name, drawn as the first row of its content rather than by the
/// navigation bar.
///
/// **What it does.** Puts the page's title where the platform's large title
/// would sit if it could — hard against the top of the screen, left aligned,
/// scrolling away as the page moves.
///
/// **Why not `.navigationTitle`.** A large title only collapses when it is
/// attached to the scroll view it tracks. Home's scrolling happens inside a
/// pager's pages while the title sat on the view holding the pager, so it had
/// nothing to follow: it stood permanently large, in a band carrying the full
/// large-title inset, about fifty points below where the same word sits in
/// Podcasts. Inline put it in the bar but gave up the fade. Drawn as a row it
/// gets both — the position and the scroll — at the cost of being this app's
/// text rather than the system's.
///
/// **How it is used.** First row of the `List`, with the navigation bar hidden.
/// It carries no background and no separator of its own, so it reads as a
/// heading over the panels rather than as an item among them.
///
/// **What it depends on.** `Spacing` and `Palette`. It holds no state.
struct PageTitle: View {

    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.snug)
            .listRowInsets(EdgeInsets(
                top: Spacing.snug, leading: Spacing.section,
                bottom: 0, trailing: Spacing.section))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}
