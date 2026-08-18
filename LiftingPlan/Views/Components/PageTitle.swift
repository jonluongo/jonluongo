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
/// **How it is used.** With the navigation bar hidden, either as the first row
/// of the `List` or above one — Home puts it above its pager, because a title
/// inside the pages swiped sideways along with the workouts, and the name of
/// the screen is not one of the things being swiped between. It carries its own
/// padding so it sits identically in both places, and no background or
/// separator, so it reads as a heading over the panels rather than an item among
/// them.
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
            .padding(.horizontal, Spacing.section)
            // Enough that the title clears a sheet's rounded top edge and its
            // grabber. On a full screen this reads as ordinary breathing room
            // under the status bar; in a sheet it is the difference between a
            // heading and a heading jammed into a corner.
            .padding(.top, Spacing.major)
            .padding(.bottom, Spacing.snug)
            // Zero, so the padding above is the only thing positioning it and
            // the same figure applies whether it is in a list or above one.
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}
