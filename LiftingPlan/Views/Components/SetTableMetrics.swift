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
/// The set and check columns are below `TapTarget.minimum`, which the interface
/// spec calls the app's worst platform finding: the completion checkbox is the
/// most-tapped control in the product at 30×28. Widening it is a change to how
/// the row is laid out — the columns it shares a row with have to give up the
/// space — and belongs with the logging screen's own work rather than here.
/// The numbers are stated in one place first so that change is one edit.
enum SetTableMetrics {

    /// The set-number badge, and the completion check at the other end.
    static let setColumnWidth: CGFloat = 30

    /// The same, so the table's two ends match.
    static let checkColumnWidth: CGFloat = 30

    /// The weight field and the work field.
    static let entryColumnWidth: CGFloat = 62

    /// The height of an entry field.
    static let entryHeight: CGFloat = 34

    /// The height of the set badge and the completion check.
    static let controlHeight: CGFloat = 28

    /// Between columns.
    static let columnGutter: CGFloat = Spacing.snug
}
