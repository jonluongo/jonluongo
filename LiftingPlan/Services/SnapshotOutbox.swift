import Foundation
import SwiftData
import LiftingKit

/// Sends the store out to the shared folder, and holds on to why it could not.
///
/// Build one with the app's transport, the `ModelContext`, and the loaded
/// catalog; call `exportSnapshot()` when the app backgrounds and read
/// `errorMessage` to show what went wrong. It is the outbound mirror of
/// `DocumentInbox`: that one takes in what the coach wrote, this one writes
/// what he reads.
///
/// **A failed export is shown, not logged.** iCloud being signed out, or the
/// container being unreachable, breaks the outbound half permanently — the Mac
/// keeps reading a snapshot that is weeks stale, which is worse than reading
/// nothing because stale data does not look like absence. So the failure is
/// held here and surfaced the next time the lifter is looking at the app,
/// exactly as an unreadable plan is.
///
/// **The store is read on the main actor; iCloud is not touched there.**
/// `ModelContext` fetches stay where SwiftData requires them, but resolving the
/// ubiquity container can block for seconds and Apple documents it as a call
/// that must not run on the main thread. `TrainingSnapshot` is a pure value
/// type, so it crosses to a background task and the resolution and file write
/// happen there.
///
/// Depends on: `DocumentTransport`, `TrainingSnapshot` and
/// `ExerciseCatalogProviding` from `LiftingKit`, `SnapshotExporter`, and the
/// store's `ModelContext`.
@MainActor
@Observable
final class SnapshotOutbox {

    /// What went wrong the last time a snapshot was written, ready to show.
    /// `nil` when the last attempt succeeded, or when none has been made.
    private(set) var errorMessage: String?

    private let transport: any DocumentTransport
    /// The same transport, when it is one that can say why a file has not
    /// reached iCloud. `nil` for a plain folder — a test's temporary directory
    /// has no upload to fail.
    private var uploads: ICloudDocumentTransport? { transport as? ICloudDocumentTransport }
    private let context: ModelContext
    private let catalog: any ExerciseCatalogProviding

    init(
        transport: any DocumentTransport,
        context: ModelContext,
        catalog: any ExerciseCatalogProviding
    ) {
        self.transport = transport
        self.context = context
        self.catalog = catalog
    }

    /// What the lifter is told when the file was written but iCloud will not
    /// take it. It names iCloud's own reason rather than paraphrasing: *Quota
    /// exceeded* is the sentence that tells him what to do.
    private static func notDelivered(_ reason: String) -> String {
        "Your record was saved on this phone but iCloud has not taken it, so "
            + "your coach is reading an older one. iCloud says: \(reason)"
    }

    /// What the lifter has already been shown and closed, so a failure that has
    /// not changed does not meet him at every launch.
    private var dismissed: String?

    /// Clears a reported failure, after the lifter has been shown it.
    func dismissError() {
        dismissed = errorMessage
        errorMessage = nil
    }

    /// Reports a failure unless it is the one he has already read and closed.
    ///
    /// **A permanent failure is the ordinary case here.** A full iCloud account
    /// does not fix itself between sessions, so every export says the same
    /// thing, and raising it again each time he opens the app is the alert
    /// nagging rather than informing. Anything *different* is new and is shown;
    /// an export that goes through forgets what was closed, so the next problem
    /// is heard. The same rule `DocumentInbox` follows, for the same reason.
    private func report(_ failure: String?) {
        errorMessage = failure == dismissed ? nil : failure
        if failure == nil { dismissed = nil }
    }

    /// Writes the current state of the store where Claude can read it.
    ///
    /// The failure is held rather than thrown because the caller is a scene
    /// transition with nowhere to return an error to. It is not discarded:
    /// `errorMessage` is what the UI puts in front of the lifter, and the store
    /// is still the record, so the next export writes the snapshot again.
    func exportSnapshot() async {
        do {
            // On the main actor, where reading the container's context belongs.
            let snapshot = try SnapshotExporter.export(
                from: context, catalogVersion: catalog.version
            )
            // Off it, where resolving iCloud belongs.
            try await Self.write(snapshot, through: transport)
            // **Written is not delivered.** The write above is a local one into
            // the ubiquity container; carrying it to the Mac is iCloud's job
            // and it can fail permanently — a full account is the ordinary
            // case. Nothing threw, the app looked fine, and the coach read
            // nothing. So the file is asked about rather than assumed.
            report(try uploads?.snapshotUploadFailure().map(Self.notDelivered))
        } catch {
            report(
                (error as? any LocalizedError)?.errorDescription
                    ?? error.localizedDescription)
        }
    }

    /// Resolves the iCloud container and writes the file, off the main actor.
    ///
    /// Detached rather than a plain `async` call: whether a `nonisolated async`
    /// function leaves the caller's actor depends on the language mode in
    /// force, and this must leave it under every one of them.
    private static func write(
        _ snapshot: TrainingSnapshot, through transport: any DocumentTransport
    ) async throws {
        try await Task.detached { try transport.writeSnapshot(snapshot) }.value
    }
}
