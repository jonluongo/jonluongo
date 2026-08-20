import Foundation
import LiftingKit

/// When each fact about the lifter was last stated.
///
/// **What it does.** Answers one question over the dated statements the phone
/// has recorded: *when did he last say anything about this?* It reports a date
/// and nothing else — not whether that is recent, not whether the fact is stale,
/// not whether to ask him again. Those are training judgements and they belong
/// to the coach.
///
/// **How it is used.** Hand it every `ProfileStatement` in the store. The
/// account page asks so a fact can carry its date the way bodyweight already
/// does, and the snapshot asks so the coach receives the same date rather than
/// inferring one from a whole-record timestamp that cannot mean it.
///
/// **What it depends on.** `ProfileStatement` from Store. It reads; it writes
/// nothing and decides nothing.
enum StatedFacts {

    /// When this fact was last spoken to, or `nil` when nothing on record has.
    ///
    /// `nil` is not "never said" — a fact stated before this build began
    /// recording statements has a value on the profile and no statement behind
    /// it. A caller says *he has not said* only when the value itself is
    /// absent; this says only when a date is known.
    static func lastStated(_ key: String, in statements: [ProfileStatement]) -> Date? {
        statements
            .filter { $0.statedKeys.contains(key) }
            .map(\.generatedAt)
            .max()
    }

    /// Every fact with a date on record, newest first — the shape a report
    /// wants when it is stating all of them at once.
    static func dates(in statements: [ProfileStatement]) -> [String: Date] {
        var newest: [String: Date] = [:]
        for statement in statements {
            for key in statement.statedKeys {
                newest[key] = max(newest[key] ?? .distantPast, statement.generatedAt)
            }
        }
        return newest
    }
}
