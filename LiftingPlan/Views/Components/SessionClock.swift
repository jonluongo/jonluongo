import SwiftUI

/// How long the lifter has been training, counting up.
///
/// **What it does.** Draws the elapsed time of a session as minutes and
/// seconds. It counts from the first ticked set rather than from the moment a
/// screen opened, so it survives closing the app and coming back — and a
/// finished session freezes at what it took rather than reporting the days
/// since.
///
/// **How it is used.** In the header beside the session's name, and only where
/// there is something to count: a session nobody has started has no elapsed
/// time, and drawing a zero would be timing how long he has looked at his
/// phone. It was a toolbar item until the session stopped being a sheet — a
/// toolbar draws its items in a capsule, which is the right shape for something
/// that can be pressed and a lie about a clock.
///
/// **What it depends on.** SwiftUI's `TimelineView` and the type ramp. It holds
/// no state and reads no model.
struct SessionClock: View {

    /// When training began — the earliest ticked set.
    let startedAt: Date
    /// When the session was marked done, which freezes the count.
    var finishedAt: Date?

    var body: some View {
        if let finishedAt {
            label(Self.elapsed(from: startedAt, to: finishedAt))
        } else {
            TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                label(Self.elapsed(from: startedAt, to: timeline.date))
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            // The same type a navigation title is set in, because that is what
            // it sits beside: a small figure in support grey read as a caption
            // hung off the bar rather than as the bar's own line. Monospaced
            // digits stay, so a counting number never reflows under a thumb.
            .font(.barbellTitle)
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
    }

    /// Minutes and seconds.
    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
