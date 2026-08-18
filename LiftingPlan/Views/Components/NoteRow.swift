import SwiftUI

extension View {

    /// Draws this line as a note under a panel: on the surface, with no panel of
    /// its own and no rule around it.
    ///
    /// **Why not a section footer.** A footer in a plain list is drawn on the
    /// default row background, so every explanatory sentence on the Account
    /// screen sat on a white band with a hairline under it — a panel wrapped
    /// around a line of explanation, which is not what a panel is for. A panel
    /// holds a record or a control; a note says something about the panel above
    /// it and belongs on the page rather than in a box.
    ///
    /// **How it is used.** `Text("…").note()` as the last row of the section it
    /// explains.
    ///
    /// **What it depends on.** `Spacing`, `Palette` and the type ramp.
    func note() -> some View {
        self
            .font(.barbellSupport)
            .foregroundStyle(Palette.muted)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Spacing.snug, leading: PanelMetrics.inset,
                bottom: Spacing.standard, trailing: PanelMetrics.inset))
    }
}
