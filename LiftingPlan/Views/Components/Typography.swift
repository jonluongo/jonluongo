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

    /// The numbers read from three feet away. `.monospacedDigit()` is part of
    /// the role, so a counting number never reflows as it changes.
    static let barbellMetric: Font = .title2.weight(.bold).monospacedDigit()

    /// The name of the thing being described.
    static let barbellTitle: Font = .headline

    /// Prose.
    static let barbellBody: Font = .body

    /// Everything that qualifies something else. Monospaced digits belong here
    /// too: most supporting text in this app is a prescription or a
    /// performance, which is mostly numerals.
    static let barbellSupport: Font = .subheadline.monospacedDigit()

    /// Column headers. Uppercasing is the call site's, since it is a property
    /// of the string rather than of the type.
    static let barbellLabel: Font = .caption2.weight(.semibold)
}
