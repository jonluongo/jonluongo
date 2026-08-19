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

    /// Whether the panel actually ends at this row's top edge, and at its
    /// bottom. A row in the middle of a table ends at neither, and drawing a
    /// line there would rule the table into bands.
    fileprivate var endsAtTop: Bool {
        switch self {
        case .first, .only: true
        case .middle, .last: false
        }
    }

    fileprivate var endsAtBottom: Bool {
        switch self {
        case .last, .only: true
        case .first, .middle: false
        }
    }
}

/// The line around a panel, drawn only where the panel actually ends.
///
/// **Why a shape and not `strokeBorder`.** A panel is drawn by its rows, so a
/// stroked rectangle on an interior row would put a line across the middle of a
/// set table at every seam — the same fault that limits the shadow to panels of
/// one row. This returns the panel's own path in a rect extended past whichever
/// end the panel does not stop at, so the horizontal edge falls outside the row
/// and the caller's `.clipped()` removes it. The corners come from
/// `UnevenRoundedRectangle` itself rather than from arcs of my own, so the line
/// follows exactly the continuous curve the fill is drawn with.
private struct PanelEdgeShape: Shape {

    let position: PanelPosition

    func path(in rect: CGRect) -> Path {
        // Far enough that the whole corner curve clears the row.
        let overshoot = Radius.panel * 2
        let top = position.endsAtTop ? rect.minY : rect.minY - overshoot
        let bottom = position.endsAtBottom ? rect.maxY : rect.maxY + overshoot
        let extended = CGRect(
            x: rect.minX, y: top, width: rect.width, height: bottom - top
        )
        .insetBy(dx: Palette.hairline / 2, dy: Palette.hairline / 2)
        return UnevenRoundedRectangle(
            topLeadingRadius: Radius.panel,
            bottomLeadingRadius: Radius.panel,
            bottomTrailingRadius: Radius.panel,
            topTrailingRadius: Radius.panel,
            style: .continuous
        )
        .path(in: extended)
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
    /// **`recessed` puts a panel further back without closing it.** What is not
    /// due yet still opens — the record has to take a session he actually
    /// trained, whenever he trained it — so a later week is drawn flat and
    /// quiet rather than greyed out or gated.
    /// The ground a panel is written on.
    ///
    /// A week he has not reached is drawn on the *surface*, so it reads as an
    /// outline waiting to be filled rather than as a panel that happens to have
    /// no shadow. Muted type and a missing lift were both absences, and an
    /// absence is invisible unless two of them are side by side — the same
    /// lesson the superset rule taught.
    private func fill(isRecorded: Bool, recessed: Bool) -> Color {
        if recessed { return Palette.surface }
        return isRecorded ? Palette.recordedPanel : Palette.panel
    }

    func panelRow(
        _ position: PanelPosition, insets: EdgeInsets = PanelMetrics.rowInsets,
        paired: Bool = false, fillsPanel: Bool = false, isRecorded: Bool = false,
        recessed: Bool = false
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
            .fill(fill(isRecorded: isRecorded, recessed: recessed))
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
            // The edge, drawn only where the panel ends — see `PanelEdgeShape`.
            // A week he has not reached takes the rule's own weight instead: it
            // is an outline on the surface rather than a panel above it, which
            // is the whole difference between what is due and what is not.
            .overlay {
                PanelEdgeShape(position: position)
                    .stroke(
                        recessed ? Palette.rule : Palette.panelEdge,
                        lineWidth: Palette.hairline)
            }
            // What keeps the extended ends of that shape off the neighbouring
            // rows.
            .clipped()
            // **No panel casts a shadow, because not every panel can.** A
            // `List` gives each row its own layer, so a blur cast by a row in
            // the middle of a set table lands on its neighbours rather than
            // behind them — and casting it instead from the panel's own
            // extended shape, which is what the edge is drawn from, paints that
            // shape's fill over the rows above and below. Rendered, the table
            // came out as three white slabs stacked over each other.
            //
            // So the edge carries it alone, which is what was missing when the
            // panels read soft: a blur says a panel is off the ground and says
            // nothing about where it stops. Every panel is drawn the same way
            // now — one fill, one hairline, one radius — which is the point.
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
