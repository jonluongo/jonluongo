import SwiftUI

/// A title, a line under it, and an optional control on the right.
///
/// **What it does.** Draws the header above a card on the logging screen — the
/// exercise's, and the group's. It is `IconCircleRow` with the circle taken off,
/// and it exists because the icon there was carrying no information: every
/// exercise drew the same dumbbell and every group the same rotate arrows, so
/// the glyph distinguished nothing from anything while indenting every title by
/// forty-eight points. A mark that is identical everywhere it appears is
/// decoration.
///
/// **How it is used.** Give it the two lines of text, and a control as
/// `trailing` when the header has one — it gets a 44pt target whatever glyph it
/// draws. `IconCircleRow` is still the right shape where the glyph varies and
/// therefore says something: an account fact, a day that is logged against one
/// that is not.
///
/// **What it depends on.** `Spacing`, `TapTarget`, and the type ramp. It reads
/// no model — callers hand it strings.
struct CardHeaderRow<Trailing: View>: View {

    let title: String
    /// The line under the title, or `nil` when there is nothing to say. Never an
    /// empty string standing in for one.
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Spacing.standard) {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(title)
                    .font(.barbellHeading)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.barbellSupport)
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            // A row with no control claims no room for one: an empty trailing
            // view given a 44pt frame would indent every row that has nothing
            // on its right.
            if Trailing.self != EmptyView.self {
                trailing()
                    .frame(minWidth: TapTarget.minimum, minHeight: TapTarget.minimum)
            }
        }
        // More above than below: the gap over a heading separates it from the
        // panel it has finished with, and the gap under it binds it to the one
        // it introduces. Equal padding made it float between the two.
        .padding(.top, Spacing.major)
        .padding(.bottom, Spacing.snug)
    }
}

extension CardHeaderRow where Trailing == EmptyView {

    /// The row without a control on the right.
    init(title: String, subtitle: String?) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
