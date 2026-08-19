import SwiftUI

/// The mark on a row that opens something.
///
/// **What it does.** Draws the chevron every openable panel in the app carries —
/// a block on the blocks list, a session on a block — so the same act is said
/// the same way wherever it appears.
///
/// **Why it is drawn rather than inherited.** A `NavigationLink` in a `List`
/// gets one from the system; a `Button` presenting a sheet does not. The blocks
/// list was links and the day rows were buttons, so the same act read two ways
/// one screen apart. Both draw this now, and neither depends on which
/// presentation it happens to use.
///
/// **What it depends on.** `Palette` and the type ramp. It reads nothing, and it
/// is never given an accessibility label: the row it sits in is a single element
/// that already announces itself as a button.
struct DisclosureChevron: View {

    /// Whether it sits on a block's own coloured field, where the muted ink it
    /// normally draws in would disappear.
    var onField: Bool = false

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.supersetSupport.weight(.semibold))
            .foregroundStyle(onField ? Color.white.opacity(0.75) : Palette.muted)
            .accessibilityHidden(true)
    }
}
