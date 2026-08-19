import SwiftUI

/// Where a row sits in the panel it belongs to.
///
/// A panel is drawn by its rows rather than around them — a `List` gives each
/// row its own background and no way to put one shape behind a whole section —
/// so each row has to know whether it is the top of the panel, the bottom, both,
/// or neither. Nothing infers it: the view that lays the rows out is the only
/// thing that knows how many there are.
enum PanelPosition {
    case first
    case middle
    case last
    /// The only row in its panel, so both ends are rounded.
    case only

    /// Where the row at `index` sits among `count` of them.
    static func at(_ index: Int, of count: Int) -> PanelPosition {
        if count <= 1 { return .only }
        if index == 0 { return .first }
        return index == count - 1 ? .last : .middle
    }

    fileprivate var topRadius: CGFloat {
        switch self {
        case .first, .only: Radius.panel
        case .middle, .last: 0
        }
    }

    fileprivate var bottomRadius: CGFloat {
        switch self {
        case .last, .only: Radius.panel
        case .first, .middle: 0
        }
    }
}

extension View {

    /// Draws this row as part of an inset panel, rounded at whichever end of it
    /// this row is.
    ///
    /// **Why this rather than `.insetGrouped`.** That style draws the panel for
    /// you and fixes its corner radius at the system's figure, which is rounder
    /// than this app wants: a softer corner reads as a card of content, and
    /// these panels hold a table of figures. The radius is `Radius.panel` and it
    /// is stated in one place, so the whole app cannot disagree with itself
    /// about how round a panel is.
    ///
    /// **How it is used.** On every row of a panel, with the position that row
    /// occupies. Pair it with `.listRowInsets` so the row's content sits inside
    /// the inset the background draws to, and use it in a `.plain` list — an
    /// inset-grouped one would draw its own panel underneath this one.
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
    func panelRow(
        _ position: PanelPosition, insets: EdgeInsets = PanelMetrics.rowInsets,
        paired: Bool = false, fillsPanel: Bool = false, isRecorded: Bool = false
    ) -> some View {
        // A panel's outer edges get more room than its inner rows, which is what
        // separates one panel from the next. Without it two panels sat flush and
        // read as a single surface with a seam across it.
        var spaced = fillsPanel
            ? EdgeInsets(
                top: 0, leading: PanelMetrics.inset,
                bottom: 0, trailing: PanelMetrics.inset)
            : insets
        // The gap between panels is the row's, the room inside the panel is the
        // content's — except when the content fills the panel, where the inside
        // room is its own padding instead.
        let closing = fillsPanel ? 0 : PanelMetrics.closing
        if position == .first || position == .only {
            spaced.top += PanelMetrics.edge + closing
        }
        if position == .last || position == .only {
            spaced.bottom += PanelMetrics.edge + closing
        }
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: position.topRadius,
            bottomLeadingRadius: position.bottomRadius,
            bottomTrailingRadius: position.bottomRadius,
            topTrailingRadius: position.topRadius,
            style: .continuous
        )
        return listRowInsets(spaced)
        .listRowBackground(
            shape
            .fill(isRecorded ? Palette.recordedPanel : Palette.panel)
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
                        .fill(Palette.accent)
                        .frame(width: PanelMetrics.pairing)
                }
            }
            // Clipped to the panel's own shape, so the rule follows the rounded
            // corner instead of squaring it. Overlaid on the shape it filled the
            // bounding box, and a superset's panel had two sharp corners that no
            // other panel had.
            .clipShape(shape)
            .padding(.horizontal, PanelMetrics.inset)
            // The gap between one panel and the next, taken off the background
            // rather than added to the row. Adding it to the row's insets — the
            // first attempt — padded the *inside* of the panel: the background
            // still filled the whole row, so the panels stayed flush and read as
            // one white column with faint seams. Space between objects has to
            // come off the object.
            .padding(.top, position == .first || position == .only ? PanelMetrics.edge : 0)
            .padding(.bottom, position == .last || position == .only ? PanelMetrics.edge : 0)
        )
    }
}
