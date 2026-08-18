import SwiftUI

/// The set table's column geometry, declared once.
///
/// **What it does.** Holds the widths that `ExerciseLogSection`'s column header
/// and `SetRowView`'s rows must agree on. They were three literals in two files
/// — 30, 62, 30 — with nothing enforcing the agreement, so the header sat over
/// its column only for as long as nobody edited one of them.
///
/// **How it is used.** Both files read these instead of writing a number. A
/// column that changes width changes here and moves both.
///
/// **What it depends on.** `Spacing`, for the gutter, and `CoreGraphics`.
///
/// Every control here meets `TapTarget.minimum`. It did not: the completion
/// check — the most-tapped control in the product, and the one pressed with
/// chalk on the hands between sets — was 30×28, or 43% of the minimum, sitting
/// eight points from a number field. The audit called it the app's worst
/// platform finding and it was right.
///
/// The flexible "previous" column absorbs the extra width, which is the correct
/// place to take it from: it is the one column that is read rather than tapped.
enum SetTableMetrics {

    /// The set-number badge, and the completion check at the other end.
    static let setColumnWidth: CGFloat = TapTarget.minimum

    /// The same, so the table's two ends match.
    static let checkColumnWidth: CGFloat = TapTarget.minimum

    /// The weight field and the work field. Wider than it was: the figures in
    /// them are monospaced now, and mono digits are broader than proportional
    /// ones, so a three-figure load needs the room rather than the shrinking.
    static let entryColumnWidth: CGFloat = 68

    /// Breathing room inside an entry field, each side.
    ///
    /// Without it the text was laid out across the field's whole width, so a
    /// prescribed range — `10-12`, `12-15` — reached both rounded edges and read
    /// as though it had overflowed. A typed number is two or three characters
    /// and keeps its full size; only the wider placeholder shrinks, which is the
    /// right way round: the number he lifted stays the biggest thing on the row.
    static let entryInset: CGFloat = 8

    /// The height of an entry field. These are tapped to focus, so they are
    /// held to the same minimum as the buttons either side of them.
    static let entryHeight: CGFloat = TapTarget.minimum

    /// The height of the set badge and the completion check.
    static let controlHeight: CGFloat = TapTarget.minimum

    /// Between columns.
    static let columnGutter: CGFloat = Spacing.snug

    /// How far the panel is inset from the edge of the screen.
    ///
    /// The same figure a heading is indented by, so the panel's edge lines up
    /// with the name of the exercise above it rather than sitting outside it.
    static let panelInset: CGFloat = Spacing.section

    /// How far a row's content sits inside the panel's own edge. Nested one
    /// step in, which is what says the row belongs to the panel rather than
    /// running to the same edge as it.
    static let contentInset: CGFloat = panelInset + Spacing.standard

    /// What surrounds one set row.
    ///
    /// The vertical figure is deliberately small. A list's default row inset is
    /// generous because most rows are a line of prose; these are lines of a
    /// table, and at the default a four-set exercise filled the screen on its
    /// own. The controls inside still clear 44pt, so the row is tight without
    /// anything on it becoming hard to hit.
    static let rowInsets = EdgeInsets(
        top: Spacing.tight, leading: contentInset,
        bottom: Spacing.tight, trailing: contentInset)

    /// What surrounds the column names. Tighter beneath, because the hairline
    /// under them belongs to the rows rather than to the label.
    static let headerInsets = EdgeInsets(
        top: Spacing.snug, leading: contentInset, bottom: 0, trailing: contentInset)
}
