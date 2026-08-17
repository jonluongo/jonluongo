import CoreGraphics

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

    /// The weight field and the work field.
    static let entryColumnWidth: CGFloat = 62

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
}
