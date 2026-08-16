import Foundation
import SwiftData
import LiftingKit

/// Carries what an earlier build recorded into the shape this one reads.
///
/// **What it does.** Runs the one-time work a schema change leaves behind.
/// SwiftData's lightweight migration keeps every row and every column — that
/// much was verified by reopening a reconstructed old store, not by reading the
/// code — but a column that was *renamed* in the model is left stranded: the
/// data is still there and nothing looks at it. Reading it across is the
/// difference between a fact the lifter stated and a fact he has to state
/// again without ever being told it was lost.
///
/// **How it is used.** `RootView` calls `run(in:)` once, on the app's own
/// context, and shows what it throws. It is idempotent: each carry-forward
/// clears the column it read, so a second run finds nothing to do. It never
/// deletes a row and never touches anything the current shape already knows.
///
/// **What it depends on.** The `Store/` models and their retired columns. It
/// invents nothing — see `UserProfile.carryForwardRetiredEquipment()` for the
/// one judgement involved, which is to carry a stated gym across and leave
/// behind the tier an old build filled in before anyone had said anything.
///
/// Throws `PersistenceError.saveFailed` when the write fails, because a
/// migration that silently did not save would look exactly like one that had
/// nothing to do.
enum StoreUpgrade {

    /// Reads every retired column that still holds something and writes it into
    /// the shape this build reads. Returns whether anything was carried.
    @discardableResult
    static func run(in context: ModelContext) throws -> Bool {
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        // Reduced rather than short-circuited: every profile is offered the
        // upgrade, including the duplicates CloudKit cannot rule out.
        let carried = profiles.reduce(false) { $0 || $1.carryForwardRetiredEquipment() }
        guard context.hasChanges else { return false }
        try context.saveOrThrow()
        return carried
    }
}
