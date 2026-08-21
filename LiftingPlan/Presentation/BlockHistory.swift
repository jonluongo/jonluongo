import Foundation
import SwiftData

/// Which block is being trained, which are behind, and what to call each one
/// that is.
///
/// **What it does.** Splits the record into the block the user is on and the
/// blocks he has finished with, and dates a finished one from what it recorded.
///
/// **How it is used.** `BlockView` draws the current block and nothing else;
/// `HistoryView` draws the rest, newest first. Both ask here rather than
/// slicing the query themselves, so *current* means one thing in the app.
///
/// **What it depends on.** `Session` from Store and `SessionListing` for the
/// grouping. It holds no state and imports no SwiftUI.
enum BlockHistory {

    /// The block being trained, or `nil` when nothing has been prescribed.
    ///
    /// The block holding the earliest unfinished session anywhere in the
    /// timeline — the same rule `SessionListing.current(in:)` uses, asked one
    /// level up. When every session is finished it is the last block, because a
    /// user who has finished everything is still *on* the block he just
    /// finished; nothing is behind him until the coach writes what is next.
    static func currentOrdinal(of sessions: [Session]) -> Int? {
        SessionListing.current(in: sessions)?.blockOrdinal
            ?? sessions.map(\.blockOrdinal).max()
    }

    /// The sessions of the block being trained, in order.
    static func current(of sessions: [Session]) -> [Session] {
        guard let ordinal = currentOrdinal(of: sessions) else { return [] }
        return sessions.filter { $0.blockOrdinal == ordinal }
            .sorted { $0.ordinal < $1.ordinal }
    }

    /// The blocks behind him, **newest first** — the way anything read backwards
    /// is listed, and the opposite of the training list, which reads forwards
    /// because that is the order it will be done in.
    ///
    /// **A block is here because it was trained, so it always has a date.** The
    /// question of what to head an untrained block with does not arise: a block
    /// nothing was logged against is not behind him, it is in front of him.
    static func past(of sessions: [Session]) -> [(ordinal: Int, sessions: [Session])] {
        guard let ordinal = currentOrdinal(of: sessions) else { return [] }
        return SessionListing.blocks(of: sessions)
            .filter { $0.ordinal < ordinal }
            .reversed()
    }

    /// When a block was trained: the day of its first recorded work to the day
    /// of its last, or one day when both fall on it.
    ///
    /// **Read off the record rather than off the plan**, because a `Session`
    /// carries no date — *when* he trained is a fact about what he did. A
    /// session that was finished without a set ticked still counts, through
    /// `finishedAt`: he went through it, and a block containing it happened.
    ///
    /// `nil` only when nothing in the block recorded anything at all, which is
    /// not a state `past(of:)` can produce.
    static func dateRange(of sessions: [Session], calendar: Calendar = .current) -> String? {
        let days = sessions.flatMap { [$0.startedAt, $0.lastPerformedAt, $0.finishedAt] }
            .compactMap { $0 }
        guard let first = days.min(), let last = days.max() else { return nil }
        guard !calendar.isDate(first, inSameDayAs: last) else { return day(first) }
        return "\(day(first)) – \(day(last))"
    }

    /// One day, as a reader of a training log would write it.
    ///
    /// Month and day, no year: the record is months long, not decades, and a
    /// year on every heading is four characters that never vary. An en dash
    /// joins the two because it is a range and not a subtraction.
    private static func day(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
