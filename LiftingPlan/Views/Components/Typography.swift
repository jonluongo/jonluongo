import SwiftUI

/// The five things text can be in this app.
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
/// - **Title** — the name of the thing: an exercise, a day, a trend, the
///   block's goal.
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

    /// The name of the thing being described.
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
