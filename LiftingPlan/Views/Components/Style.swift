import SwiftUI
import UIKit

// The app's style sheet: every colour, every type role, every distance, every
// radius and every piece of table geometry, in one file.
//
// **Why one file.** These were five, and a sixth held the panel's figures next
// to the modifier that drew them — so a question like "how far is a row inset?"
// was answered in one place and "how far is the panel inset?" in another, and
// the two drifted apart the moment somebody edited one. A style sheet is the
// kind of thing that is only trustworthy when it is exhaustive: if a view can
// find a number here, it never writes its own.
//
// **The rule this file exists to enforce.** No view states a colour, a point
// size, a gap or a radius. It asks for the job — `Palette.ink`, `Spacing.snug`,
// `.font(.barbellMetric)` — and the answer lives here, once. A number that
// appears in a view is a number nobody chose.
//
// Nothing here decides anything about training. These are drawing figures; the
// facts about lifting live in versioned JSON, as they must.

/// Every colour this app draws, named by the job it does.
///
/// **What it does.** Replaces the system's grouped-list greys — which are what
/// every stock SwiftUI app is made of — with a cool neutral scale of its own,
/// plus the one accent and the one mark that says a set happened. Seven names,
/// and a view asks for the job rather than for a shade.
///
/// **Why cool and not warm.** The app is a record kept precisely: it makes no
/// training decisions, states only what was prescribed and what was performed,
/// and refuses to invent a figure. Warm paper neutrals would dress that up as a
/// notebook, which is a friendlier object than this actually is. The greys here
/// are slightly blue, the way a measuring instrument's are, so the one warm
/// thing on the screen is the accent — and the accent only ever marks something
/// the lifter can act on.
///
/// **How it is used.** `Palette.ink`, `Palette.rule`, and so on. Each resolves
/// against the trait collection, so dark mode is the same seven jobs in darker
/// paint rather than a second design.
///
/// **What it depends on.** SwiftUI and `UIColor`'s dynamic provider. It reads no
/// state and no asset except the accent, which stays in the asset catalog
/// because the system draws it in places this app does not control.
enum Palette {

    /// Behind everything.
    static let surface = dynamic(light: 0xF2F3F5, dark: 0x0F1012)

    /// The ground a table of sets is written on.
    static let panel = dynamic(light: 0xFFFFFF, dark: 0x17181C)

    /// Hairlines. The instrument's ruling — it separates columns and rows
    /// without boxing them, which is what a card does.
    static let rule = dynamic(light: 0xD8DADF, dark: 0x2A2C32)

    /// Text and, above all, numbers.
    static let ink = dynamic(light: 0x15171A, dark: 0xF1F2F4)

    /// Anything qualifying something else: column names, units, the last
    /// session's figures.
    static let muted = dynamic(light: 0x6C7076, dark: 0x8A8F96)

    /// The one thing on screen that is not a neutral. It marks what can be
    /// acted on, and nothing else — see `PrimaryActionButton`.
    static let accent = Color.accentColor

    /// The mark that something is in the record: a ticked set, a logged
    /// session. Cool and dark enough to sit with the neutrals rather than
    /// shouting beside the accent, which is the mistake a full-width slab of
    /// system green made.
    static let recorded = dynamic(light: 0x1F7A4D, dark: 0x35C57F)

    /// The width of a hairline.
    ///
    /// A third of a point, which is one device pixel on the 3× screens this
    /// ships to and sub-pixel on nothing it runs on. It is stated rather than
    /// read from the screen: `UIScreen.main` is deprecated and main-actor bound,
    /// and a rule that has to touch the actor to know its own width is a rule
    /// that cannot be drawn from a `let`.
    static let hairline: CGFloat = 1.0 / 3.0

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {

    /// A colour from `0xRRGGBB`. Confined to `Palette`, which is the only place
    /// in the app allowed to name one.
    fileprivate convenience init(hex: Int) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The six things text can be in this app.
///
/// **What it does.** Replaces the eighteen type treatments the audit counted —
/// seven base styles, four weights and nine loose `.monospacedDigit()`
/// modifiers, for six screens — with five roles chosen by what the text *is*.
/// Every one is built on a semantic text style, so Dynamic Type carries all of
/// it and no number in this file is a point size.
///
/// **How it is used.** `.font(.barbellSupport)` and so on. Pick by role:
///
/// - **Metric** — a number the lifter reads mid-set, at arm's length: a
///   countdown, a weight, a rep count. These are the content of the logging
///   screen and they get bigger, not smaller.
/// - **Heading** — the name of a section that owns the panel beneath it: the
///   exercise a set table logs, the workout a list of exercises makes up. It
///   was `Title`, which is also what the rows *inside* those panels are drawn
///   in — so a heading and the items under it were the same weight, and nothing
///   outranked anything. A heading has to win against its own contents or it is
///   not a heading.
/// - **Title** — the name of a thing in a list: an exercise row, a day, a
///   trend.
/// - **Body** — prose. Footers, empty-state descriptions, a coach's note.
/// - **Support** — everything that qualifies something else: prescription
///   lines, previous performance, subtitles. **One** supporting size, in place
///   of the `.caption` / `.footnote` / `.subheadline` trio, which differed by
///   a point at default size and bought nothing.
/// - **Label** — column headers, uppercased. Nothing else.
///
/// Colour is not part of a role. Support and Label are almost always
/// `.secondary` and Title almost always `.primary`, but the colour is stated at
/// the call site because a role that carried one would be two decisions wearing
/// one name.
///
/// **What it depends on.** SwiftUI's semantic text styles, and nothing else —
/// no asset, no environment, no state.
extension Font {

    /// The numbers read from three feet away, set in the monospaced face.
    ///
    /// This is the app's one typographic signature and it is spent here on
    /// purpose: the whole product is a grid of figures — a load, a count, a
    /// countdown — and a monospaced face is what a column of figures is written
    /// in when the column has to be scanned rather than read. It also holds its
    /// width as a number changes, so nothing reflows under a thumb mid-set.
    /// Everything around it stays in the system face; a page set entirely in
    /// mono is a terminal, not an instrument.
    static let barbellMetric: Font = .system(.title3, design: .monospaced).weight(.semibold)

    /// The name of a section, drawn above the panel that holds its contents.
    /// A step clear of `barbellTitle` so the hierarchy is visible rather than
    /// implied by position alone.
    static let barbellHeading: Font = .title3.weight(.bold)

    /// The name of a thing inside a list.
    static let barbellTitle: Font = .headline

    /// Prose.
    static let barbellBody: Font = .body

    /// Everything that qualifies something else. Monospaced digits belong here
    /// too: most supporting text in this app is a prescription or a
    /// performance, which is mostly numerals.
    static let barbellSupport: Font = .subheadline.monospacedDigit()

    /// Column headers. Uppercasing is the call site's, since it is a property
    /// of the string rather than of the type — as is the tracking, which is a
    /// layout modifier rather than part of a font. `Label.tracking` below is the
    /// figure to use: letter-spaced capitals are how a measuring instrument
    /// labels a scale, and at this size they stop reading as shouting and start
    /// reading as engraving.
    static let barbellLabel: Font = .caption2.weight(.semibold)

    /// The tracking a `barbellLabel` is drawn with.
    static let labelTracking: CGFloat = 0.8
}

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

    /// The mark that says a thing is in the record — see `RecordedMark`.
    static let mark: CGFloat = 6

    /// The panel a table of figures is written on.
    ///
    /// Drawn `.continuous` everywhere, which is the part that matters: a
    /// circular arc meets the straight edge at an angle the eye catches, and a
    /// continuous curve does not. Six points of circular arc read as a hard
    /// corner however small the number is, which is why cutting the radius did
    /// not make the panel quieter — it made it sharper.
    static let panel: CGFloat = 12

    /// Surfaces that float over content: the rest bar.
    static let large: CGFloat = 20

    /// Every radius, smallest first. For tests, as with `Spacing.all`.
    ///
    /// The order is the size of the thing drawn, not the order they were
    /// written: an entry field is small and takes a small curve, a panel is a
    /// surface and takes a larger one, and the bar floating over content takes
    /// the largest. A panel tighter than the field inside it was the mistake
    /// that made the panels read as hard.
    static let all: [CGFloat] = [mark, small, panel, large]
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

    /// What surrounds one set row.
    ///
    /// The vertical figure is deliberately small. A list's default row inset is
    /// generous because most rows are a line of prose; these are lines of a
    /// table, and at the default a four-set exercise filled the screen on its
    /// own. The controls inside still clear 44pt, so the row is tight without
    /// anything on it becoming hard to hit.
    static let rowInsets = EdgeInsets(
        top: Spacing.tight, leading: PanelMetrics.contentInset,
        bottom: Spacing.tight, trailing: PanelMetrics.contentInset)

    /// What surrounds the column names. Tighter beneath, because the hairline
    /// under them belongs to the rows rather than to the label.
    static let headerInsets = EdgeInsets(
        top: Spacing.snug, leading: PanelMetrics.contentInset,
        bottom: 0, trailing: PanelMetrics.contentInset)
}

/// The geometry every panel shares.
///
/// It lives here rather than in `SetTableMetrics` because a panel is not a set
/// table: the block list, the account record and the exercise detail all draw
/// one, and each of them had been given the background without the matching
/// content inset — so the icon in a row sat four points inside the panel's edge
/// while the text beside it sat twenty-eight. `panelRow` applies both now, and
/// the pair cannot come apart.
enum PanelMetrics {

    /// How far the panel is inset from the edge of the screen. The same figure
    /// a heading is indented by, so a panel's edge lines up with the name above
    /// it rather than sitting outside it.
    static let inset: CGFloat = Spacing.section

    /// How far a row's content sits inside the panel's own edge. Nested one
    /// step in, which is what says the row belongs to the panel rather than
    /// running to the same edge as it.
    static let contentInset: CGFloat = inset + Spacing.standard

    /// The extra room a panel's first and last rows take, which is the gap one
    /// panel keeps from the next.
    static let edge: CGFloat = Spacing.standard

    /// The width of the rule marking movements performed as one superset. Thin
    /// enough to read as an edge rather than a block of colour.
    static let pairing: CGFloat = 3

    /// What surrounds an ordinary row of a panel.
    static let rowInsets = EdgeInsets(
        top: Spacing.snug, leading: contentInset, bottom: Spacing.snug, trailing: contentInset)

    /// The room a panel keeps inside its own top and bottom edges, beyond what
    /// the row already has. A set row's content is a field whose underline sits
    /// at the very bottom of it, so without this the last rule in a table lands
    /// against the panel's edge while the title above breathes.
    static let closing: CGFloat = Spacing.standard
}
