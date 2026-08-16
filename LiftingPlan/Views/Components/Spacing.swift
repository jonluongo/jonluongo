import CoreGraphics

/// The five gaps this app draws, and nothing else.
///
/// **What it does.** Names every distance between two things on screen. A view
/// asks for `Spacing.snug`, never for `8`, so the question "how far apart should
/// these sit?" has five possible answers instead of infinitely many.
///
/// **How it is used.** As the argument to `spacing:` and `.padding(_:_:)`
/// everywhere in `Views/`. Pick by job, not by size: the job names below are the
/// contract. When two jobs seem to fit, take the lighter one — the scale
/// deliberately has no 2, because the difference between 2 and 4 is a difference
/// nobody can see and everybody has to maintain.
///
/// **What it depends on.** `CoreGraphics`, for `CGFloat`. Nothing else, and
/// nothing depends on the app's state — these are constants, not settings.
enum Spacing {

    /// A glyph and its own text; the vertical padding inside a list row; the
    /// gap between a title and the subtitle that belongs to it.
    static let tight: CGFloat = 4

    /// Elements inside one component; the gutter between table columns.
    static let snug: CGFloat = 8

    /// An icon and the text block beside it; a cluster of controls.
    static let standard: CGFloat = 12

    /// One component and the next; a screen's edge inset.
    static let section: CGFloat = 16

    /// Distinct groups on a sheet.
    static let major: CGFloat = 24

    /// The whole scale, in order. Exists so a test can assert its size — the
    /// vocabulary staying small is the property worth guarding.
    static let all: [CGFloat] = [tight, snug, standard, section, major]
}

/// The two corner radii this app draws.
///
/// **What it does.** Names the roundness of a rectangle by what the rectangle
/// is, so the same shape cannot be 8 in one file and 20 in another.
///
/// **How it is used.** `.rect(cornerRadius: Radius.small)` and friends. Where a
/// shape is drawn twice — a background and the stroke over it — both read the
/// same constant, which is what stops a one-line edit producing a hairline
/// mismatch.
///
/// **What it depends on.** `CoreGraphics`. Nothing else.
enum Radius {

    /// Inline controls that sit in a row: entry fields, badges.
    static let small: CGFloat = 8

    /// Surfaces that float over content: the rest bar.
    static let large: CGFloat = 20

    /// Both radii, small first. For tests, as with `Spacing.all`.
    static let all: [CGFloat] = [small, large]
}

/// The smallest a control may be.
///
/// **What it does.** States Apple's 44pt minimum once, as a number the layout
/// can be built from rather than a rule somebody remembers.
///
/// **How it is used.** `.frame(minWidth:minHeight:)` on anything tappable, or
/// a `.contentShape` of this size over a smaller glyph when the visual weight
/// of a 44pt symbol would be wrong. The components in `Views/Components/`
/// enforce it; a control that cannot meet it is a layout that needs changing,
/// not a number that needs lowering.
///
/// **What it depends on.** `CoreGraphics`.
enum TapTarget {

    /// 44pt, from Apple's Human Interface Guidelines. Not negotiable, and not
    /// a starting point for a compromise.
    static let minimum: CGFloat = 44
}
