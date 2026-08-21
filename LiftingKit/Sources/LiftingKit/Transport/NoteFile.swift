import Foundation

/// The coach's two markdown notes, by name.
///
/// **What it does.** Names `user.md` and `program.md` in one place, so the phone
/// and the server cannot disagree about which file is which — the same reason
/// `DocumentFolder` names `plan.json` once.
///
/// **What is in each.** `user` holds who the lifter is: his objective, his
/// background, his injuries, what he avoids and why, his equipment, his
/// bodyweight. `program` holds why this programme — the approach, what is being
/// progressed, what to watch, and what makes a given block a deload.
///
/// **Neither is ever parsed.** The app renders them. Every field that used to
/// live on a profile was display-only, which is what made it prose; the moment
/// a value has to come back out, that value belongs in a table.
public enum NoteFile: String, Sendable, CaseIterable {
    case user
    case program

    public var filename: String { "\(rawValue).md" }

    /// What an unwritten note says, and what the coach edits beneath.
    ///
    /// **An empty file gives an anchored edit nothing to anchor to.** The
    /// headings are the anchors: `update_notes` states the text it expects to
    /// replace, so the coach's first write needs something already there to
    /// replace. It is also what the app draws before he has written anything —
    /// a profile that has been told nothing must read as *not known*, never as a
    /// plausible default.
    public var template: String {
        switch self {
        case .user:
            """
            # The lifter

            ## Objective
            _Not yet stated._

            ## Background
            _Not yet stated._

            ## Injuries and limits
            _None on record._

            ## What he avoids, and why
            _Nothing on record._

            ## Equipment
            _Not yet stated._

            ## Bodyweight
            _No readings on record._
            """
        case .program:
            """
            # This programme

            ## The approach
            _Not yet stated._

            ## What is being progressed
            _Not yet stated._

            ## What to watch
            _Not yet stated._
            """
        }
    }
}
