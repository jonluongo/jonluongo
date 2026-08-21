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
}
