import Foundation
import SwiftData
import LiftingKit

/// One thing the lifter said about himself, and when he said it.
///
/// **What it does.** Records that an arriving `ProfileUpdate` stated certain
/// facts, on the date it was written. One row per applied update, holding the
/// keys it spoke to and nothing else.
///
/// **Why the profile cannot answer this.** `UserProfile` holds one value per
/// fact and one `updatedAt` for all of them, so an update to the goal today
/// restamps a constraint stated eighteen months ago. The coach reads
/// `constraints` and cannot tell a shoulder that is sore now from one that was
/// sore before the last two blocks — which are different instructions. A series
/// of dated statements can tell them apart; a single record never could.
///
/// **What it does not hold.** Not the values. The profile already carries what
/// is currently true, and a second copy would be a second answer to the same
/// question. This says *when*, and the profile says *what*. Bodyweight and
/// baselines are absent for the same reason in reverse: each is already a dated
/// series where it is stored.
///
/// **What it depends on.** `ProfileUpdate.keysStated` for the names, which are
/// the wire's own, so a fact renamed in the format is renamed here too.
@Model
final class ProfileStatement {

    /// The `ProfileUpdate.id` this came from, so the same document applied twice
    /// is one statement rather than two.
    var id: UUID = UUID()

    /// When the coach wrote it. This is the date that answers *when did he say
    /// this*, rather than when the phone happened to take it in.
    var generatedAt: Date = Date()

    /// When the phone applied it. Kept apart from `generatedAt` because a phone
    /// that was off for a week takes in a week-old statement, and reporting the
    /// day it arrived as the day he said it would be a small lie in the one
    /// place this type exists to be honest about.
    var appliedAt: Date = Date()

    private var statedKeysRaw: [String] = []

    /// The facts this update spoke to, as the wire names them.
    var statedKeys: Set<String> {
        get { Set(statedKeysRaw) }
        set { statedKeysRaw = newValue.sorted() }
    }

    init(id: UUID = UUID(), generatedAt: Date = Date(), appliedAt: Date = Date(),
         statedKeys: Set<String> = []) {
        self.id = id
        self.generatedAt = generatedAt
        self.appliedAt = appliedAt
        self.statedKeysRaw = statedKeys.sorted()
    }
}
