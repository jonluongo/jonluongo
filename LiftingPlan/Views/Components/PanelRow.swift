import SwiftUI

/// Several rows drawn as one panel.
///
/// **What it does.** Stacks what it is given inside a single list row and draws
/// the panel around the stack, so a table of facts is one object on the screen
/// rather than a run of rows that happen to touch.
///
/// **Why it exists.** A `List` gives every row its own layer, so a panel spread
/// over five rows could not be lifted: a shadow cast by an interior row lands on
/// its neighbours rather than behind them. The app had both kinds — the session's
/// exercise panels drawn as one row and lifted, the account and routine facts
/// drawn as five and flat — and Jon read the difference straight off the screen:
/// *"Why aren't these panels the same with the same shadows?"* They are one thing
/// now, and there is one panel style rather than a lifted one and a flat one.
///
/// **How it is used.** Wrap the rows. The spacing between them is `Spacing.major`
/// rather than the `Spacing.section` two `PanelMetrics.rowInsets` add up to,
/// because a `List` also gave every row a 44pt floor: stacked at the insets
/// alone, a table of facts came out a third tighter than the same table had been
/// the day before. Give it `isRecorded` where what it holds is in the record,
/// and `recessed` where it is not due yet.
///
/// **What it depends on.** `panelRow`, which draws it, and `Spacing`.
struct Panel<Content: View>: View {

    var isRecorded = false
    var recessed = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.major) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelRow(isRecorded: isRecorded, recessed: recessed)
            .listRowSeparator(.hidden)
    }
}

extension View {

    /// Draws this view as a panel, outside a `List`.
    ///
    /// **The same fill, hairline, radius and shadow `panelRow` gives a row**,
    /// for the one place a panel is not a list row: the rest sheet. The two draw
    /// from the same tokens, so a panel there and a panel on the logging screen
    /// cannot come to look different — which is the whole reason this is a
    /// modifier rather than a shape written out a second time.
    func panelSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        return background(Palette.panel, in: shape)
            .overlay { shape.strokeBorder(Palette.panelEdge, lineWidth: Palette.hairline) }
            .shadow(
                color: Palette.panelShadow,
                radius: PanelMetrics.shadowRadius, y: PanelMetrics.shadowY)
    }

    /// Draws this row as a panel of its own.
    ///
    /// **Why this rather than `.insetGrouped`.** That style draws the panel for
    /// you and fixes its corner radius at the system's figure, which is rounder
    /// than this app wants: a softer corner reads as a card of content, and
    /// these panels hold a table of figures. The radius is `Radius.panel` and it
    /// is stated in one place, so the whole app cannot disagree with itself
    /// about how round a panel is.
    ///
    /// **One row is one panel.** There is no first, middle or last: a panel of
    /// several things is `Panel`, which stacks them into a single row. Rows that
    /// each knew where they sat in a shared panel were the reason half the app's
    /// panels could not cast a shadow — see `Panel` — and the position they
    /// carried is what let two panels of the same kind come out looking
    /// different.
    ///
    /// **How it is used.** In a `.plain` list — an inset-grouped one would draw
    /// its own panel underneath this one.
    ///
    /// **`fillsPanel` is for a row that is a button.** The row's content is
    /// normally inset from the panel's edge, which leaves a band of panel that
    /// is drawn but not tappable — so tapping a session near its edge did
    /// nothing, and the panel looked like a button that sometimes ignored you.
    /// With it, the content is handed the panel's whole area and pads itself by
    /// `PanelMetrics.buttonInsets`, which is the same room by a different owner.
    /// **`isRecorded` colours the panel rather than adding to it.** What a row
    /// holds being in the record is a state that varies down a list, which is
    /// exactly what a panel's own ground can say without spending a line or a
    /// slot on it.
    /// **`recessed` puts a panel further back without closing it.** What is not
    /// due yet still opens — the record has to take a session he actually
    /// trained, whenever he trained it — so a later week is drawn flat and
    /// quiet rather than greyed out or gated.
    func panelRow(
        insets: EdgeInsets = PanelMetrics.rowInsets,
        paired: Bool = false, fillsPanel: Bool = false, isRecorded: Bool = false,
        recessed: Bool = false
    ) -> some View {
        // A panel's edges get more room than the row's own content, which is
        // what separates one panel from the next. Without it two panels sat
        // flush and read as a single surface with a seam across it.
        var spaced = fillsPanel
            ? EdgeInsets(
                top: 0, leading: PanelMetrics.inset,
                bottom: 0, trailing: PanelMetrics.inset)
            : insets
        // The gap between panels is the row's, the room inside the panel is the
        // content's — except when the content fills the panel, where the inside
        // room is its own padding instead.
        let closing = fillsPanel ? 0 : PanelMetrics.closing
        spaced.top += PanelMetrics.edge + closing
        spaced.bottom += PanelMetrics.edge + closing
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        return listRowInsets(spaced)
        .listRowBackground(
            shape
            .fill(panelFill(isRecorded: isRecorded, recessed: recessed))
            .overlay(alignment: .leading) {
                // The mark that two movements are one superset.
                //
                // The first attempt was an absence: two exercises sharing a
                // panel with no gap, where every other pair has one. Rendered,
                // that read as three separate exercises — a missing gap is
                // invisible unless you are comparing two gaps side by side, and
                // a lifter mid-set is looking at one exercise. A signal has to
                // be present, not withheld.
                //
                // It is a rule rather than a word because "Superset A" was a
                // code with a glossary, and this is the one thing in the app
                // that ever draws it: a line down the edge of the movements that
                // are performed together and rested after as one.
                if paired {
                    Rectangle()
                        .fill(Palette.ink)
                        .frame(width: PanelMetrics.pairing)
                }
            }
            // Clipped to the panel's own shape, so the rule follows the rounded
            // corner instead of squaring it. Overlaid on the shape it filled the
            // bounding box, and a superset's panel had two sharp corners that no
            // other panel had.
            .clipShape(shape)
            // A week he has not reached takes the rule's own weight instead of
            // the panel edge: it is an outline on the surface rather than a
            // panel above it, which is the whole difference between what is due
            // and what is not.
            .overlay {
                shape.strokeBorder(
                    recessed ? Palette.rule : Palette.panelEdge,
                    lineWidth: Palette.hairline)
            }
            // Every panel is lifted the same way, because every panel is one
            // row. What is not due yet is the one exception: it sits on the
            // surface rather than above it.
            .shadow(
                color: recessed ? .clear : Palette.panelShadow,
                radius: PanelMetrics.shadowRadius,
                y: PanelMetrics.shadowY)
            .padding(.horizontal, PanelMetrics.inset)
            // The gap between one panel and the next, taken off the background
            // rather than added to the row. Adding it to the row's insets — the
            // first attempt — padded the *inside* of the panel: the background
            // still filled the whole row, so the panels stayed flush and read as
            // one white column with faint seams. Space between objects has to
            // come off the object.
            .padding(.vertical, PanelMetrics.edge)
        )
    }

}

/// The ground a panel is written on.
///
/// A week he has not reached is drawn on the *surface*, so it reads as an
/// outline waiting to be filled rather than as a panel that happens to have no
/// shadow. Muted type and a missing lift were both absences, and an absence is
/// invisible unless two of them are side by side — the same lesson the superset
/// rule taught.
private func panelFill(isRecorded: Bool, recessed: Bool) -> Color {
    if recessed { return Palette.surface }
    return isRecorded ? Palette.recordedPanel : Palette.panel
}
