import SwiftUI

/// How long the user trained.
///
/// **What it does.** Counts from the first ticked set, second by second, and
/// stops when the session is finished — at the moment Finish was pressed, or at
/// the last ticked set if that came later. The start is a fact the record
/// already holds, so the count survives closing the app, backgrounding and
/// syncing without anything new being stored.
///
/// **It ticks, rather than advancing a set at a time.** Anchoring both ends to
/// logged sets made it stop dead between them: it only moved when a set was
/// ticked, which is a clock that reports the past rather than one you can train
/// against. Finishing is what stops it — which is also the answer to a session
/// left open overnight reading `23:49:59`: the session was never finished, and
/// the number is the honest elapsed time until it is.
///
/// **How it is used.** In the header beside the session's name, and only where
/// there is something to count: a session nobody has started has no elapsed
/// time, and drawing a zero would be timing how long he has looked at his
/// phone. It was a toolbar item until the session stopped being a sheet — a
/// toolbar draws its items in a capsule, which is the right shape for something
/// that can be pressed and a lie about a clock.
///
/// **What it depends on.** SwiftUI's `TimelineView` and the type ramp. It holds
/// no state and reads no model — the dates are handed to it.
struct SessionClock: View {

    /// When training began — the earliest ticked set.
    let startedAt: Date
    /// The latest ticked set. Where a finished session's count ends, when Finish
    /// was pressed before it.
    let lastLoggedAt: Date
    /// When the session was marked done. `nil` while it is still being trained,
    /// which is when the count runs.
    var finishedAt: Date?

    var body: some View {
        if let finishedAt {
            label(Self.elapsed(from: startedAt, to: Self.end(finishedAt, lastLoggedAt)))
        } else {
            // A second is the whole resolution here: the figure states seconds,
            // so anything finer would redraw the bar without changing it.
            TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                label(Self.elapsed(from: startedAt, to: max(timeline.date, lastLoggedAt)))
            }
        }
    }

    /// Where a finished session's count stops: when it was marked done, or the
    /// last tick — whichever is later.
    ///
    /// Never the earlier of the two. A session marked finished before its last
    /// set was ticked — an out-of-order write, or a set corrected after the fact
    /// — would otherwise report less time than the record holds evidence for,
    /// and at the limit report none at all.
    nonisolated static func end(_ finishedAt: Date?, _ lastLoggedAt: Date) -> Date {
        guard let finishedAt else { return lastLoggedAt }
        return max(finishedAt, lastLoggedAt)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            // The same type a navigation title is set in, because that is what
            // it sits beside: a small figure in support grey read as a caption
            // hung off the bar rather than as the bar's own line. Monospaced
            // digits stay, so a counting number never reflows under a thumb.
            .font(.supersetTitle)
            .foregroundStyle(Palette.ink)
            .monospacedDigit()
    }

    /// Minutes and seconds, and hours once there is an hour to state.
    ///
    /// Minutes alone kept counting past sixty rather than rolling over, so a
    /// session resumed the next day read `1429:59` — a number with no unit
    /// anybody uses. The hour field appears only when it is not zero, so an
    /// ordinary session is still four characters wide.
    nonisolated static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        guard hours > 0 else { return String(format: "%d:%02d", minutes, seconds % 60) }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
    }
}
