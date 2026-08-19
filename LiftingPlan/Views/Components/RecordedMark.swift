import SwiftUI

/// The one mark this app uses to say a thing is in the record.
///
/// **What it does.** Draws a filled square with a check in it — on a set that
/// was ticked, on a day that was logged, beside the word on a finished session.
/// One shape, one colour, one meaning, wherever the claim is made.
///
/// **Why it exists.** The same statement was drawn three ways: a filled square
/// on a set row, a bare checkmark glyph on a day row, and a labelled check at
/// the foot of a session. Three marks for one fact reads as three different
/// facts, and the weakest of them — a thin glyph alone in a wide row — barely
/// registered as a signal at all.
///
/// **Empty is a shape too.** An unticked set draws the same square outlined
/// rather than nothing, because a row with a mark and a row with a gap do not
/// compare; two squares, one filled, do.
///
/// **What it depends on.** `Palette` and `Radius`. It holds no state and decides
/// nothing: whether a thing is recorded is asked elsewhere.
struct RecordedMark: View {

    /// Whether the thing is in the record.
    let isRecorded: Bool
    /// Whether the empty state draws an outline. A set row compares ticked rows
    /// against unticked ones and needs it; a list of days marks only what is
    /// done and would otherwise carry a column of empty boxes.
    var showsEmpty: Bool = true

    var body: some View {
        if isRecorded || showsEmpty {
            RoundedRectangle(cornerRadius: Radius.mark, style: .continuous)
                .fill(isRecorded ? Palette.accent : .clear)
                .stroke(isRecorded ? Palette.accent : Palette.rule, lineWidth: 1.5)
                .frame(width: Self.side, height: Self.side)
                .overlay {
                    if isRecorded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.panel)
                    }
                }
        }
    }

    /// Big enough to read at arm's length, small enough not to compete with the
    /// figures it sits beside.
    private static let side: CGFloat = 24
}
