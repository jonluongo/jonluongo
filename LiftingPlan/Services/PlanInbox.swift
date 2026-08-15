import Foundation
import SwiftData
import LiftingKit

/// Tells its caller that a plan has turned up in the shared folder.
///
/// Conform to it to announce arrivals however a platform announces them —
/// `UbiquitousPlanWatcher` uses `NSMetadataQuery`, because a file arriving from
/// iCloud does not reliably fire ordinary filesystem events — and conform a
/// fake to it in tests to announce one on demand. It carries no document: what
/// arrived is the transport's business, not the watcher's.
///
/// Depends on: nothing. Deliberately: this is the seam that keeps
/// `PlanInbox` free of iCloud.
@MainActor
protocol PlanArrivalWatching: AnyObject {

    /// Begins watching. `onArrival` is called once per announcement, on the
    /// main actor. Calling it again while already watching does nothing.
    func start(onArrival: @escaping () -> Void)

    /// Stops watching and releases whatever the watch was holding.
    func stop()
}

/// Imports a plan the moment one arrives, so the lifter never hunts for a
/// refresh button.
///
/// Build one with the app's transport, a watcher, the `ModelContext`, and the
/// loaded catalog; call `start()` once and read `errorMessage` to show what
/// went wrong. It is the only caller of `PlanImporter`, which makes this the
/// whole of the app's inbound half of the loop: Claude writes `plan.json` on
/// the Mac, iCloud carries it, this notices and imports it.
///
/// **Absence and corruption are told apart.** A transport with no plan in it is
/// the ordinary state of a lifter who has not been given one, and passes in
/// silence. A plan that is there but unreadable — malformed, or naming an
/// exercise the catalog does not have — sets `errorMessage` and imports
/// nothing, because a corrupt plan that read as an empty one would leave the
/// lifter staring at an empty screen with no idea why.
///
/// Re-importing is safe: a `PlanDocument` carries a stable identity and
/// `PlanImporter` returns the existing block rather than duplicating it, so the
/// document is left in place rather than consumed.
///
/// Depends on: `DocumentTransport` and `ExerciseCatalogProviding` from
/// `LiftingKit`, `PlanArrivalWatching`, `PlanImporter`, and the store's
/// `ModelContext`.
@MainActor
@Observable
final class PlanInbox {

    /// What went wrong the last time a plan was read, ready to show. `nil` when
    /// nothing has gone wrong — which includes there being no plan yet.
    private(set) var errorMessage: String?

    private let transport: any DocumentTransport
    private let watcher: any PlanArrivalWatching
    private let context: ModelContext
    private let catalog: any ExerciseCatalogProviding

    init(
        transport: any DocumentTransport,
        watcher: any PlanArrivalWatching,
        context: ModelContext,
        catalog: any ExerciseCatalogProviding
    ) {
        self.transport = transport
        self.watcher = watcher
        self.context = context
        self.catalog = catalog
    }

    /// Starts watching for plans.
    ///
    /// No read happens here. The watcher announces what is already in the
    /// folder as its first event, so the plan waiting at launch is imported the
    /// same way as one that lands mid-session — and resolving the iCloud
    /// container, which can block, stays off the launch path.
    func start() {
        watcher.start { [weak self] in self?.importWaitingPlan() }
    }

    /// Stops watching. The store keeps whatever was already imported.
    func stop() {
        watcher.stop()
    }

    /// Clears a reported failure, after the lifter has been shown it.
    func dismissError() {
        errorMessage = nil
    }

    /// Reads whatever is waiting and imports it.
    ///
    /// The failure is held rather than thrown because the caller is an arrival
    /// announcement with nowhere to return an error to. It is not discarded:
    /// `errorMessage` is what the UI puts in front of the lifter, and the
    /// document stays in the folder, so a fixed plan imports on its next
    /// announcement.
    func importWaitingPlan() {
        do {
            // No plan yet is the normal state, not something to report.
            guard let document = try transport.readPlan() else { return }
            try PlanImporter.import(document, into: context, catalog: catalog)
            errorMessage = nil
        } catch {
            errorMessage = (error as? any LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
