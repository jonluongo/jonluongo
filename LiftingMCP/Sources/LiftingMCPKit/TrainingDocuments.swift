import Foundation
import LiftingKit

/// The Mac's half of the loop: read the snapshot, write the plan, and record
/// what has been learned about the lifter.
///
/// Hand one to a `ToolRunner`. `DocumentFolder` from `LiftingKit` conforms, so
/// in production this is the shared iCloud folder and nothing here reimplements
/// a path, a file name, or an encoder. Tests supply an in-memory stand-in and
/// so can cover the case that matters most — a lifter whose app has never
/// backgrounded — without an iCloud account.
///
/// The two `location` strings exist so an error can name the folder it looked
/// in. That sentence is the whole difference between an error the owner can act
/// on and one he has to guess at.
///
/// **`nil` and "broken" are different answers**, exactly as on the phone's
/// side: `readSnapshot()` returns `nil` when the app has not written one yet
/// and throws when a snapshot is there but unreadable.
///
/// Depends on: `TrainingSnapshot` and `PlanDocument` from `LiftingKit`.
public protocol TrainingDocuments: Sendable {

    /// The snapshot the app last wrote, or `nil` when it has never written one.
    func readSnapshot() throws -> TrainingSnapshot?

    /// Puts a plan where the app will pick it up, replacing any earlier one.
    func writePlan(_ plan: PlanDocument) throws

    /// Puts a profile update where the app will pick it up, replacing any
    /// earlier one. The app applies each update's identity once, so replacing
    /// an update that has already landed does not re-impose it.
    func writeProfileUpdate(_ update: ProfileUpdate) throws

    /// The update sitting in the folder, or `nil` when there is none.
    ///
    /// The folder holds one at a time, so a writer reads this before replacing
    /// it: an update the phone has not taken in yet must be folded into the new
    /// one rather than overwritten, or the facts it carried are lost silently.
    func readProfileUpdate() throws -> ProfileUpdate?

    /// Where `readSnapshot()` looks, for an error message to name.
    var snapshotLocation: String { get }

    /// Where `writePlan(_:)` writes, for a report to name.
    var planLocation: String { get }

    /// Where `writeProfileUpdate(_:)` writes, for a report to name.
    var profileUpdateLocation: String { get }
}

/// The shared folder is already the transport; it only needs to say where it is.
///
/// `readSnapshot()`, `writePlan(_:)` and `writeProfileUpdate(_:)` are
/// `DocumentFolder`'s own — the server deliberately does not restate a file name
/// or an encoding strategy, because the one place both clients agree about those
/// is `LiftingKit`.
extension DocumentFolder: TrainingDocuments {

    public var snapshotLocation: String {
        url.appending(path: Self.snapshotFilename).path(percentEncoded: false)
    }

    public var planLocation: String {
        url.appending(path: Self.planFilename).path(percentEncoded: false)
    }

    public var profileUpdateLocation: String {
        url.appending(path: Self.profileUpdateFilename).path(percentEncoded: false)
    }
}
