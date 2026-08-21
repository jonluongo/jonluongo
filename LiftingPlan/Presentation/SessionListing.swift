import Foundation
import LiftingKit

/// What the list of training says about a block and a session.
///
/// **What it does.** Names a block, names a session, and says where each stands
/// — the whole of what a screen showing the training needs in words.
///
/// **It replaced three types that answered the same question.**
/// `RoutineListing`, `BlockSelection` and `SessionPhrasing` were 281 lines
/// between them, all about what a row says, all named for a routine — a word the
/// domain no longer has. There are no routines, no block labels and no weekdays,
/// so most of what they did cannot be asked any more: which block is current,
/// what an unnamed block is called, whether a block is a deload, and what
/// weekday a session falls on.
///
/// **Nothing here is a verdict.** An earlier session is where the training went,
/// not a failure, and nothing reads as a score, a streak or a grade. The record
/// holds whether a session was finished and nothing about how it went.
///
/// **What it depends on.** `Session` from Store. It reads and never writes.
enum SessionListing {

    /// Where a session stands.
    enum Standing {

        /// The session the user is on — the first he has not finished. There
        /// is at most one.
        case current

        /// A session he has been through.
        case finished

        /// One he has not reached.
        case upcoming

        /// The standing, said into a row's own label.
        ///
        /// The list does not group under headings: the order already puts the
        /// open session first and the mark already changes with it. The word
        /// survives here because a screen reader hears one row at a time and
        /// would otherwise hear a name with no standing at all.
        var spoken: String {
            switch self {
            case .current: "Current session"
            case .finished: "Finished session"
            case .upcoming: "Upcoming session"
            }
        }
    }

    /// What a block is called.
    ///
    /// **A number, and nothing else.** Blocks have no names: what makes block 3
    /// an accumulation block is a line the coach wrote in `PROGRAM.md`, and a
    /// label here would be the second place that fact lived.
    static func blockTitle(_ ordinal: Int) -> String {
        "Block \(ordinal)"
    }

    /// What a session is called: what the coach named it, or where it sits.
    ///
    /// The fallback says the position rather than inventing a name. It used to
    /// say the weekday, which was the app deciding when the user trains from a
    /// field the plan no longer has.
    static func sessionTitle(_ session: Session) -> String {
        session.focus.isEmpty ? "Session \(session.ordinal)" : session.focus
    }

    /// Where one session stands, given the one he is on.
    ///
    /// **`current` is passed in rather than worked out here, and that is the
    /// point.** Being current is a fact about the whole timeline: it is the
    /// first unfinished session there is. Asking a list of sessions to work it
    /// out makes it a fact about *that* list — so a screen drawing block 1 and
    /// block 2 separately would mark a current session in each of them, and the
    /// user would be told he is in two places.
    static func standing(of session: Session, current: Session?) -> Standing {
        if session.finishedAt != nil { return .finished }
        return session === current ? .current : .upcoming
    }

    /// The session the user is on: the first he has not finished.
    ///
    /// `nil` once he has finished every session prescribed, which is the
    /// truthful answer on that day rather than a gap to be filled. It is also
    /// the cue that the next block is due.
    static func current(in sessions: [Session]) -> Session? {
        sessions.first { $0.finishedAt == nil }
    }

    /// The sessions of each block, in order, with the block first that he is on.
    static func blocks(of sessions: [Session]) -> [(ordinal: Int, sessions: [Session])] {
        Dictionary(grouping: sessions, by: \.blockOrdinal)
            .map { (ordinal: $0.key, sessions: $0.value.sorted { $0.ordinal < $1.ordinal }) }
            .sorted { $0.ordinal < $1.ordinal }
    }
}
