import SwiftUI

/// How long the lifter trained.
///
/// **What it does.** Draws how long a session took: the span from its first
/// ticked set to its last. Both ends are facts the record already holds, so it
/// survives closing the app, backgrounding and syncing without anything new
/// being stored, and it advances as sets are ticked rather than by the clock on
/// the wall.
///
/// **It does not run while nothing is happening.** Counting live to now meant a
/// session left open overnight reported the hours since it began — `1429:59` on
/// a workout that took an hour — which is the screen stating something nobody
/// did. Between the first tick and the last is the only span the record can
/// vouch for.
///
/// **How it is used.** In the header beside the session's name, and only where
/// there is something to count: a session nobody has started has no elapsed
/// time, and drawing a zero would be timing how long he has looked at his
/// phone. It was a toolbar item until the session stopped being a sheet — a
/// toolbar draws its items in a capsule, which is the right shape for something
/// that can be pressed and a lie about a clock.
///
/// **What it depends on.** The type ramp. It holds no state and reads no
/// model — the two dates are handed to it.
struct SessionClock: View {

    /// When training began — the earliest ticked set.
    let startedAt: Date
    /// The latest ticked set. The count reaches here and stops.
    let lastLoggedAt: Date
    /// When the session was marked done. It ends the count at the moment it was
    /// finished rather than at the last tick, since a lifter can finish a
    /// session some minutes after his last set.
    var finishedAt: Date?

    var body: some View {
        label(Self.elapsed(from: startedAt, to: Self.end(finishedAt, lastLoggedAt)))
    }

    /// Where the count stops: when the session was marked done, or the last tick
    /// — whichever is later.
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
            .font(.barbellTitle)
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
