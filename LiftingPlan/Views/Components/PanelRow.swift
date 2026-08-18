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
    func panelRow(
        _ position: PanelPosition, insets: EdgeInsets = PanelMetrics.rowInsets
    ) -> some View {
        listRowInsets(insets)
        .listRowBackground(
            UnevenRoundedRectangle(
                topLeadingRadius: position.topRadius,
                bottomLeadingRadius: position.bottomRadius,
                bottomTrailingRadius: position.bottomRadius,
                topTrailingRadius: position.topRadius
            )
            .fill(Palette.panel)
            .padding(.horizontal, PanelMetrics.inset)
        )
    }
}
